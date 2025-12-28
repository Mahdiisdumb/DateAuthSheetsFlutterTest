import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';

import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/auth_io.dart' as auth;

// Single spreadsheet ID for all data
const String mainSpreadsheetId = '1lbyjJoNYydylvhVbn4vKzAbMG85eX7q-oaaj4hIa3QM';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const LoginScreen(),
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final usernameCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();
  bool busy = false;
  bool isSignup = false;

  Future<void> ensureSheetExists(sheets.SheetsApi api, String sheetName) async {
    try {
      final spreadsheet = await api.spreadsheets.get(mainSpreadsheetId);
      final sheetsList = spreadsheet.sheets ?? [];
      final sheetExists = sheetsList.any((s) => s.properties?.title == sheetName);
      
      if (!sheetExists) {
        await api.spreadsheets.batchUpdate(
          sheets.BatchUpdateSpreadsheetRequest(requests: [
            sheets.Request(
              addSheet: sheets.AddSheetRequest(
                properties: sheets.SheetProperties(title: sheetName),
              ),
            ),
          ]),
          mainSpreadsheetId,
        );
      }
    } catch (e) {
      throw Exception('Could not verify/create sheet $sheetName: $e');
    }
  }

  Future<void> handleAuth() async {
    if (kIsWeb) {
      _snack('Service accounts do not work on Web.', error: true);
      return;
    }

    final username = usernameCtrl.text.trim();
    final password = passwordCtrl.text.trim();

    if (username.isEmpty || password.isEmpty) {
      _snack('Please enter username and password', error: true);
      return;
    }

    setState(() => busy = true);
    auth.AutoRefreshingAuthClient? client;

    try {
      final jsonStr = await rootBundle.loadString('assets/credential.json');
      final credsMap = json.decode(jsonStr);
      final creds = auth.ServiceAccountCredentials.fromJson(credsMap);

      client = await auth.clientViaServiceAccount(creds, [
        sheets.SheetsApi.spreadsheetsScope,
      ]);

      final api = sheets.SheetsApi(client);
      
      // Ensure USERS sheet exists
      await ensureSheetExists(api, 'USERS');

      if (isSignup) {
        final existing = await api.spreadsheets.values.get(
          mainSpreadsheetId,
          'USERS!A:A',
        );

        if (existing.values != null) {
          for (var row in existing.values!) {
            if (row.isNotEmpty && row[0].toString() == username) {
              _snack('Username already exists', error: true);
              return;
            }
          }
        }
        final nextRow = (existing.values?.length ?? 0) + 1;
        final range = 'USERS!A$nextRow:B$nextRow';
        final body = sheets.ValueRange(
          values: [
            [username, password],
          ],
        );
        await api.spreadsheets.values.update(
          body,
          mainSpreadsheetId,
          range,
          valueInputOption: 'RAW',
        );
        _snack('Account created successfully!');
        setState(() => isSignup = false);
      } else {
        final data = await api.spreadsheets.values.get(
          mainSpreadsheetId,
          'USERS!A:B',
        );
        bool found = false;
        if (data.values != null) {
          for (var row in data.values!) {
            if (row.length >= 2 &&
                row[0].toString() == username &&
                row[1].toString() == password) {
              found = true;
              break;
            }
          }
        }
        if (found) {
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => MainEventPage(username: username),
              ),
            );
          }
        } else {
          _snack('Invalid username or password', error: true);
        }
      }
    } catch (e) {
      _snack('Error: $e', error: true);
    } finally {
      client?.close();
      if (mounted) setState(() => busy = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? Colors.red : null),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isSignup ? 'Create Account' : 'Login')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: usernameCtrl,
              decoration: const InputDecoration(
                labelText: 'Username',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordCtrl,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: busy ? null : handleAuth,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              child: busy
                  ? const CircularProgressIndicator()
                  : Text(isSignup ? 'Sign Up' : 'Login'),
            ),
            const SizedBox(height: 16),
            if (!isSignup)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ForgotPasswordPage(),
                      ),
                    );
                  },
                  child: const Text('Forgot Password?'),
                ),
              ),
            TextButton(
              onPressed: () {
                setState(() => isSignup = !isSignup);
              },
              child: Text(
                isSignup
                    ? 'Already have an account? Login'
                    : 'Don\'t have an account? Sign Up',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});
  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final usernameCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  bool busy = false;

  Future<void> ensureSheetExists(sheets.SheetsApi api, String sheetName) async {
    try {
      final spreadsheet = await api.spreadsheets.get(mainSpreadsheetId);
      final sheetsList = spreadsheet.sheets ?? [];
      final sheetExists = sheetsList.any((s) => s.properties?.title == sheetName);
      
      if (!sheetExists) {
        await api.spreadsheets.batchUpdate(
          sheets.BatchUpdateSpreadsheetRequest(requests: [
            sheets.Request(
              addSheet: sheets.AddSheetRequest(
                properties: sheets.SheetProperties(title: sheetName),
              ),
            ),
          ]),
          mainSpreadsheetId,
        );
      }
    } catch (e) {
      throw Exception('Could not verify/create sheet $sheetName: $e');
    }
  }

  Future<void> handleReset() async {
    final username = usernameCtrl.text.trim();
    final email = emailCtrl.text.trim();
    if (username.isEmpty || email.isEmpty) {
      _snack('Please enter username and email', error: true);
      return;
    }
    setState(() => busy = true);
    auth.AutoRefreshingAuthClient? client;
    try {
      final jsonStr = await rootBundle.loadString('assets/credential.json');
      final credsMap = json.decode(jsonStr);
      final creds = auth.ServiceAccountCredentials.fromJson(credsMap);

      client = await auth.clientViaServiceAccount(creds, [
        sheets.SheetsApi.spreadsheetsScope,
      ]);

      final api = sheets.SheetsApi(client);
      
      // Ensure USERRESET sheet exists
      await ensureSheetExists(api, 'USERRESET');

      final body = sheets.ValueRange(values: [
        [username, email, DateTime.now().toIso8601String(), 'requested'],
      ]);

      await api.spreadsheets.values.append(
        body,
        mainSpreadsheetId,
        'USERRESET!A:D',
        valueInputOption: 'RAW',
        insertDataOption: 'INSERT_ROWS',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset request submitted. You will receive an email with your new password.')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      _snack('Error: $e', error: true);
    } finally {
      client?.close();
      if (mounted) setState(() => busy = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? Colors.red : null),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset Password')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: usernameCtrl,
              decoration: const InputDecoration(
                labelText: 'Username',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emailCtrl,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: busy ? null : handleReset,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              child: busy
                  ? const CircularProgressIndicator()
                  : const Text('Request Reset'),
            ),
          ],
        ),
      ),
    );
  }
}

class MainEventPage extends StatefulWidget {
  final String username;
  const MainEventPage({super.key, required this.username});

  @override
  State<MainEventPage> createState() => _MainEventPageState();
}

class _MainEventPageState extends State<MainEventPage> {
  final eventNameCtrl = TextEditingController();
  DateTime? selectedDate;
  TimeOfDay? startTime;
  TimeOfDay? endTime;
  bool busy = false;

  Future<void> ensureSheetExists(sheets.SheetsApi api, String sheetName) async {
    try {
      final spreadsheet = await api.spreadsheets.get(mainSpreadsheetId);
      final sheetsList = spreadsheet.sheets ?? [];
      final sheetExists = sheetsList.any((s) => s.properties?.title == sheetName);
      
      if (!sheetExists) {
        await api.spreadsheets.batchUpdate(
          sheets.BatchUpdateSpreadsheetRequest(requests: [
            sheets.Request(
              addSheet: sheets.AddSheetRequest(
                properties: sheets.SheetProperties(title: sheetName),
              ),
            ),
          ]),
          mainSpreadsheetId,
        );
      }
    } catch (e) {
      throw Exception('Could not verify/create sheet $sheetName: $e');
    }
  }

  Future<void> pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date != null) {
      setState(() => selectedDate = date);
    }
  }

  Future<void> pickStartTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time != null) {
      setState(() => startTime = time);
    }
  }

  Future<void> pickEndTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time != null) {
      setState(() => endTime = time);
    }
  }

  Future<void> uploadEvent() async {
    if (kIsWeb) {
      _snack('Service accounts do not work on Web.', error: true);
      return;
    }

    final eventName = eventNameCtrl.text.trim();
    if (eventName.isEmpty ||
        selectedDate == null ||
        startTime == null ||
        endTime == null) {
      _snack('Please fill in all fields', error: true);
      return;
    }

    setState(() => busy = true);
    auth.AutoRefreshingAuthClient? client;

    try {
      final jsonStr = await rootBundle.loadString('assets/credential.json');
      final credsMap = json.decode(jsonStr);
      final creds = auth.ServiceAccountCredentials.fromJson(credsMap);

      client = await auth.clientViaServiceAccount(creds, [
        sheets.SheetsApi.spreadsheetsScope,
      ]);

      final api = sheets.SheetsApi(client);
      
      // Ensure EVENTS sheet exists
      await ensureSheetExists(api, 'EVENTS');
      
      final existing = await api.spreadsheets.values.get(
        mainSpreadsheetId,
        'EVENTS!A:A',
      );
      final nextRow = (existing.values?.length ?? 0) + 1;

      final dateStr = DateFormat('yyyy-MM-dd').format(selectedDate!);
      final startStr = startTime!.format(context);
      final endStr = endTime!.format(context);

      final range = 'EVENTS!A$nextRow:E$nextRow';
      final body = sheets.ValueRange(
        values: [
          [widget.username, eventName, startStr, endStr, dateStr],
        ],
      );

      await api.spreadsheets.values.update(
        body,
        mainSpreadsheetId,
        range,
        valueInputOption: 'RAW',
      );

      _snack('Event created successfully!');
      eventNameCtrl.clear();
      setState(() {
        selectedDate = null;
        startTime = null;
        endTime = null;
      });
    } catch (e) {
      _snack('Error: $e', error: true);
    } finally {
      client?.close();
      if (mounted) setState(() => busy = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? Colors.red : null),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Welcome, ${widget.username}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.list),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EventViewerPage(username: widget.username),
                ),
              );
            },
            tooltip: 'View My Events',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Create New Event',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: eventNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Event Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              title: Text(
                selectedDate == null
                    ? 'Select Date'
                    : 'Date: ${DateFormat('yyyy-MM-dd').format(selectedDate!)}',
              ),
              trailing: const Icon(Icons.calendar_today),
              onTap: pickDate,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              title: Text(
                startTime == null
                    ? 'Select Start Time'
                    : 'Start: ${startTime!.format(context)}',
              ),
              trailing: const Icon(Icons.access_time),
              onTap: pickStartTime,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              title: Text(
                endTime == null
                    ? 'Select End Time'
                    : 'End: ${endTime!.format(context)}',
              ),
              trailing: const Icon(Icons.access_time),
              onTap: pickEndTime,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: busy ? null : uploadEvent,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              child: busy
                  ? const CircularProgressIndicator()
                  : const Text('Create Event'),
            ),
          ],
        ),
      ),
    );
  }
}

class EventViewerPage extends StatefulWidget {
  final String username;
  const EventViewerPage({super.key, required this.username});

  @override
  State<EventViewerPage> createState() => _EventViewerPageState();
}

class _EventViewerPageState extends State<EventViewerPage> {
  List<Map<String, String>> events = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadEvents();
  }

  Future<void> loadEvents() async {
    if (kIsWeb) {
      setState(() => loading = false);
      return;
    }

    auth.AutoRefreshingAuthClient? client;

    try {
      final jsonStr = await rootBundle.loadString('assets/credential.json');
      final credsMap = json.decode(jsonStr);
      final creds = auth.ServiceAccountCredentials.fromJson(credsMap);

      client = await auth.clientViaServiceAccount(creds, [
        sheets.SheetsApi.spreadsheetsScope,
      ]);

      final api = sheets.SheetsApi(client);

      final data = await api.spreadsheets.values.get(
        mainSpreadsheetId,
        'EVENTS!A:E',
      );

      final userEvents = <Map<String, String>>[];
      if (data.values != null) {
        for (var row in data.values!) {
          if (row.isNotEmpty && row[0].toString() == widget.username) {
            userEvents.add({
              'uploader': row.length > 0 ? row[0].toString() : '',
              'eventName': row.length > 1 ? row[1].toString() : '',
              'startTime': row.length > 2 ? row[2].toString() : '',
              'endTime': row.length > 3 ? row[3].toString() : '',
              'date': row.length > 4 ? row[4].toString() : '',
            });
          }
        }
      }

      setState(() {
        events = userEvents;
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading events: $e')));
      }
      setState(() => loading = false);
    } finally {
      client?.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Events')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : events.isEmpty
          ? const Center(
              child: Text('No events found', style: TextStyle(fontSize: 18)),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: events.length,
              itemBuilder: (context, index) {
                final event = events[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text(
                      event['eventName'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Date: ${event['date']}'),
                        Text(
                          'Time: ${event['startTime']} - ${event['endTime']}',
                        ),
                      ],
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            ),
    );
  }
}