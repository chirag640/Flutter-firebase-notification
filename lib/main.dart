import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart';
import 'dart:convert';
import 'auth_screen.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Background message handler - must be a top-level function
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Handling a background message: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  await Firebase.initializeApp();
  
  // Set background message handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  
  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  
  @override
  void initState() {
    super.initState();
    _initializeLocalNotifications();
    _initializeMessaging();
  }

  // Initialize flutter_local_notifications
  void _initializeLocalNotifications() {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(android: androidSettings, iOS: iosSettings);
    _localNotifications.initialize(initSettings);
  }


    // Show local notification in status bar (foreground)
  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    const androidDetails = AndroidNotificationDetails(
      'fcm_channel',
      'FCM Notifications',
      channelDescription: 'Channel for FCM notifications',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      details,
      payload: message.data.toString(),
    );
  }

  // Initialize FCM and handle token refresh
  Future<void> _initializeMessaging() async {
    // Request notification permissions
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    print('User granted permission: ${settings.authorizationStatus}');

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Got a message whilst in the foreground!');
      print('Message data: ${message.data}');

      // Show local notification in status bar
      if (message.notification != null) {
        print('Message also contained a notification: ${message.notification}');
        _showLocalNotification(message);
        _showNotificationDialog(message.notification!);
      }
    });
  

    // Handle notification taps when app is in background/terminated
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('A new onMessageOpenedApp event was published!');
      _handleNotificationTap(message);
    });

    // Handle notification tap when app is launched from terminated state
    RemoteMessage? initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }

    // Listen for token refresh
    _messaging.onTokenRefresh.listen((String token) {
      print('FCM Token refreshed: $token');
      _updateUserToken(token);
    });

    // Get initial token and update Firestore if user is authenticated
    if (_auth.currentUser != null) {
      await _updateUserToken();
    }
  }

  // Update FCM token in Firestore for the current user
  Future<void> _updateUserToken([String? token]) async {
    final User? user = _auth.currentUser;
    if (user == null) return;

    try {
      // Get current FCM token if not provided
      token ??= await _messaging.getToken();
      
      if (token != null) {
        // Update user document with new token
        await _firestore.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'email': user.email,
          'token': token,
          'lastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        
        print('FCM token updated in Firestore: $token');
      }
    } catch (e) {
      print('Error updating FCM token: $e');
    }
  }

  // Show notification dialog when app is in foreground
  void _showNotificationDialog(RemoteNotification notification) {
    // Check if the widget is mounted and context is valid
    if (!mounted) return;
    
    // Ensure we have a valid Material context before showing dialog
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      
      // Find the navigator context
      final navigatorContext = _navigatorKey.currentContext;
      if (navigatorContext == null) return;
      
      showDialog(
        context: navigatorContext,
        builder: (context) => AlertDialog(
          title: Text(notification.title ?? 'Notification'),
          content: Text(notification.body ?? 'No message body'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    });
  }

  // Handle notification tap
  void _handleNotificationTap(RemoteMessage message) {
    print('Notification tapped: ${message.data}');
    // Add your navigation logic here based on message data
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FCM Demo',
      navigatorKey: _navigatorKey,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: StreamBuilder<User?>(
        stream: _auth.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          
          if (snapshot.hasData) {
            // User is authenticated, update FCM token
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _updateUserToken();
            });
            return HomeScreen(user: snapshot.data!);
          } else {
            // User is not authenticated, show auth screen
            return AuthScreen(onUserAuthenticated: _updateUserToken);
          }
        },
      ),
    );
  }
}

// Home screen for authenticated users
class HomeScreen extends StatelessWidget {
  final User user;
  
  const HomeScreen({super.key, required this.user});

  // Helper to send dynamic notification using FCM v1 HTTP API
  Future<void> _sendDynamicNotification(BuildContext context) async {
    final nameController = TextEditingController();
    final roleController = TextEditingController();

    // Show dialog to get name and role
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Send Dynamic Notification'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: roleController,
                decoration: const InputDecoration(labelText: 'Role'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop({
                  'name': nameController.text.trim(),
                  'role': roleController.text.trim(),
                });
              },
              child: const Text('Send'),
            ),
          ],
        );
      },
    );

    if (result == null || result['name']!.isEmpty || result['role']!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name and role are required.')));
      return;
    }

    final name = result['name']!;
    final role = result['role']!;

    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final token = doc.data()?['token'] as String?;
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No FCM token found.')));
      return;
    }

    try {
      // Get access token for FCM v1 API
      final accessToken = await _getAccessToken();
      if (accessToken == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to get access token. Please check service account configuration.'),
        ));
        return;
      }

      // Your Firebase project ID (replace with your actual project ID)
      const String projectId = 'notificationdemo-a3431';
      final url = Uri.parse('https://fcm.googleapis.com/v1/projects/$projectId/messages:send');
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      };

      final message = {
        'message': {
          'token': token,
          'notification': {
            'title': 'User Info: $name ($role)',
            'body': 'Name: $name\nRole: $role',
          },
          'data': {
            'click_action': 'FLUTTER_NOTIFICATION_CLICK',
            'customData': 'dynamic',
            'name': name,
            'role': role,
            'timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
          },
          'android': {
            'notification': {
              'icon': 'stock_ticker_update',
              'color': '#f45342',
              'sound': 'default',
            },
          },
          'apns': {
            'payload': {
              'aps': {
                'sound': 'default',
              },
            },
          },
        },
      };

      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode(message),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Dynamic notification sent!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed: ${response.statusCode}\n${response.body}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Get OAuth 2.0 access token for FCM v1 API
Future<String?> _getAccessToken() async {
  try {
    // Load service account JSON from assets
    final jsonString = await rootBundle.loadString('assets/service_account.json');
    final serviceAccountJson = jsonDecode(jsonString);

    final credentials = ServiceAccountCredentials.fromJson(serviceAccountJson);
    final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];
    final client = await clientViaServiceAccount(credentials, scopes);
    final accessToken = client.credentials.accessToken.data;
    client.close();
    return accessToken;
  } catch (e) {
    print('Error getting access token: $e');
    return null;
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FCM Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ...existing code...
            ElevatedButton.icon(
              icon: const Icon(Icons.send),
              label: const Text('Send Dynamic Notification'),
              onPressed: () => _sendDynamicNotification(context),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            // ...existing code...
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'User Information',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Email: ${user.email}'),
                    Text('UID: ${user.uid}'),
                  ],
                ),
              ),
            ),
            // ...existing code...
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'FCM Token Status',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    StreamBuilder<DocumentSnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .doc(user.uid)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.hasData && snapshot.data!.exists) {
                          final data = snapshot.data!.data() as Map<String, dynamic>;
                          final token = data['token'] as String?;
                          final lastUpdated = data['lastUpdated'] as Timestamp?;
                          
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('✅ FCM token registered'),
                              if (lastUpdated != null)
                                Text(
                                  'Last updated: ${lastUpdated.toDate().toString().substring(0, 19)}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              const SizedBox(height: 8),
                              const Text(
                                'Token (last 20 chars):',
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                              Text(
                                token != null && token.length > 20
                                    ? '...${token.substring(token.length - 20)}'
                                    : token ?? 'No token',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          );
                        } else {
                          return const Text('⏳ Registering FCM token...');
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            // ...existing code...
            const SizedBox(height: 16),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Notification Status',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text('🔔 Notifications enabled'),
                    Text('📱 Ready to receive push notifications'),
                    SizedBox(height: 8),
                    Text(
                      'Your FCM token is automatically updated when:',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    Text('• You sign up or log in'),
                    Text('• The app starts and you\'re authenticated'),
                    Text('• Firebase refreshes your token'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
