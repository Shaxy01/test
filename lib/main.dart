import 'package:flutter/material.dart';
import 'package:roslibdart/roslibdart.dart';
import 'dart:convert';
import 'package:flutter_joystick/flutter_joystick.dart';
import 'package:provider/provider.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => RobotsState(),
      child: MyApp(),
    ),
  );
}

class RobotsState extends ChangeNotifier {
  List<bool> robotsActive = List.filled(6, false);
  String robotNamespace = 'tb2_';
  String serverAddress = 'ws://192.168.5.143:9090'; // Domyślny adres serwera

  void updateRobotsActive(List<bool> activeList) {
    robotsActive = List.from(activeList);
    notifyListeners();
  }

  void updateRobotNamespace(String newNamespace) {
    robotNamespace = newNamespace;
    notifyListeners();
  }

  void updateServerAddress(String newAddress) {
    if (!newAddress.startsWith('ws://')) {
      serverAddress = 'ws://$newAddress';
    } else {
      serverAddress = newAddress;
    }
    notifyListeners();
  }
}

class RosManager {
  late Ros ros;
  late Topic cmdVelTopic;
  late Topic chatterTopic;
  bool isConnected = false;
  String lastMessage = "No topics available";

  RosManager(BuildContext context) {
    String url = Provider.of<RobotsState>(context, listen: false).serverAddress;
    ros = Ros(url: url);
    connect(context);
  }

  void connect(BuildContext context) {
    ros.connect();
    isConnected = true;

    cmdVelTopic = Topic(
      ros: ros,
      name: '/cmd_vel',
      type: 'geometry_msgs/Twist',
      reconnectOnClose: true,
      queueLength: 10,
      queueSize: 10,
    );

    String namespace = Provider.of<RobotsState>(context, listen: false).robotNamespace;
    subscribeToChatter(context, namespace);
  }

  void subscribeToChatter(BuildContext context, String namespace) {
    chatterTopic = Topic(
      ros: ros,
      name: '/topic',
      type: 'std_msgs/msg/String',
    );
    chatterTopic.subscribe((message) {
      lastMessage = jsonEncode(message);
      List<bool> newRobotsActive = List.from(Provider.of<RobotsState>(context, listen: false).robotsActive);
      for (int i = 1; i <= newRobotsActive.length; i++) {
        newRobotsActive[i - 1] = lastMessage.contains('$namespace$i');
      }
      Provider.of<RobotsState>(context, listen: false).updateRobotsActive(newRobotsActive);
      print('Message from: /topic: $message');

      return Future.value(); // Dodano zwracanie Future<void>
    });
  }

  void setRobotCmdVelTopic(int robotNumber, String namespace) {
    cmdVelTopic = Topic(
      ros: ros,
      name: '/$namespace$robotNumber/cmd_vel',
      type: 'geometry_msgs/Twist',
      reconnectOnClose: true,
      queueLength: 10,
      queueSize: 10,
    );
    print('Zasubskrybowano do: /$namespace$robotNumber/cmd_vel');
  }

  void publishMessage(Map<String, dynamic> message) {
    if (!isConnected) {
      print('Nie można opublikować wiadomości: ROS nie jest połączony');
      return;
    }
    cmdVelTopic.publish(message);
  }

  void disconnect() {
    ros.close();
    isConnected = false;
  }
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final rosManager = RosManager(context);

    return MaterialApp(
      title: 'Robot Remote Control',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
      ),
      debugShowCheckedModeBanner: false, // Dodano tę linię
      home: HomePage(rosManager: rosManager),
    );
  }
}


class HomePage extends StatelessWidget {
  final RosManager rosManager;

  HomePage({required this.rosManager});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Choose a Robot'),
      ),
      body: Center(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView.builder(
                itemCount: 6,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: RobotButton(number: index + 1, rosManager: rosManager),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10.0),
              child: TextField(
                decoration: InputDecoration(
                    labelText: 'Robot Namespace',
                    hintText: 'tb2_'
                ),
                onChanged: (value) {
                  Provider.of<RobotsState>(context, listen: false).updateRobotNamespace(value);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10.0),
              child: TextField(
                decoration: InputDecoration(
                    labelText: 'Server Address',
                    hintText: '192.168.5.143:9090'
                ),
                onChanged: (value) {
                  Provider.of<RobotsState>(context, listen: false).updateServerAddress(value);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}



class RobotButton extends StatelessWidget {
  final int number;
  final RosManager rosManager;

  RobotButton({required this.number, required this.rosManager});

  @override
  Widget build(BuildContext context) {
    return Consumer<RobotsState>(
      builder: (context, robotsState, child) {
        bool isActive = robotsState.robotsActive[number - 1];
        return Center(
          child: SizedBox(
            width: 200, // Set a fixed width for the button
            child: ElevatedButton(
              key: ValueKey(isActive),
              style: ElevatedButton.styleFrom(
                backgroundColor: isActive ? Colors.green : Colors.blueAccent,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => RobotControlPage(robotNumber: number, rosManager: rosManager),
                  ),
                );
              },
              child: Text('Robot $number'),
            ),
          ),
        );
      },
    );
  }
}

class RobotControlPage extends StatefulWidget {
  final int robotNumber;
  final RosManager rosManager;

  RobotControlPage({Key? key, required this.robotNumber, required this.rosManager})
      : super(key: key);

  @override
  _RobotControlPageState createState() => _RobotControlPageState();
}

class _RobotControlPageState extends State<RobotControlPage> {
  double maxLinearSpeed = 0.2; // Maksymalna prędkość liniowa
  double maxAngularSpeed = 2.0; // Maksymalna prędkość kątowa
  @override
  void initState() {
    super.initState();
    String namespace = Provider.of<RobotsState>(context, listen: false).robotNamespace;
    widget.rosManager.setRobotCmdVelTopic(widget.robotNumber, namespace);
  }

  @override
  void dispose() {
    widget.rosManager.cmdVelTopic.unsubscribe();
    super.dispose();
    print('Wyrejestrowano');
  }

  void sendJoystickCommand(StickDragDetails details) {
    double dx = details.x * maxAngularSpeed;
    double dy = details.y * maxLinearSpeed;

    // Przekształć kąt i odległość na prędkość liniową i obrotową
    double linearVelocity = -dy;
    double angularVelocity = -dx;

    var message = {
      'linear': {'x': linearVelocity, 'y': 0.0, 'z': 0.0},
      'angular': {'x': 0.0, 'y': 0.0, 'z': angularVelocity}
    };
    widget.rosManager.publishMessage(message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('TurtleBot2_${widget.robotNumber}'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Joystick(
              mode: JoystickMode.all,
              listener: sendJoystickCommand,
            ),
            Slider(
              value: maxLinearSpeed,
              min: 0,
              max: 1,
              divisions: 10,
              label: "Linear Speed: ${maxLinearSpeed.toStringAsFixed(1)}",
              onChanged: (value) {
                setState(() {
                  maxLinearSpeed = value;
                });
              },
            ),
            Slider(
              value: maxAngularSpeed,
              min: 0,
              max: 2,
              divisions: 10,
              label: "Angular Speed: ${maxAngularSpeed.toStringAsFixed(1)}",
              onChanged: (value) {
                setState(() {
                  maxAngularSpeed = value;
                });
              },
            ),
            Text(
              'Control the Robot',
              style: TextStyle(fontSize: 24),
            ),
            SizedBox(height: 20),
            SizedBox(height: 20),
            ShowTopicsButton(rosManager: widget.rosManager),
            ConnectionStatus(rosManager: widget.rosManager),
            SwitchRobotButton(robotNumber: widget.robotNumber, rosManager: widget.rosManager),
          ],
        ),
      ),
    );
  }
}

class ShowTopicsButton extends StatelessWidget {
  final RosManager rosManager;

  const ShowTopicsButton({Key? key, required this.rosManager})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () {
        showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              //title: Text('Dostępne Tematy'),
              content: SingleChildScrollView( // Dodaj SingleChildScrollView
                child: Text(rosManager.lastMessage),
              ),
            );
          },
        );
      },
      child: Text('Show ROS topics'),
    );
  }
}

class ConnectionStatus extends StatelessWidget {
  final RosManager rosManager;

  const ConnectionStatus({Key? key, required this.rosManager}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Text(rosManager.isConnected ? '' : '');
  }
}

class SwitchRobotButton extends StatelessWidget {
  final int robotNumber;
  final RosManager rosManager;

  const SwitchRobotButton(
      {Key? key, required this.robotNumber, required this.rosManager})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () {
        int nextRobotNumber = (robotNumber % 6) + 1;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) =>
                RobotControlPage(
                    robotNumber: nextRobotNumber, rosManager: rosManager),
          ),
        );
      },
      child: Text('Switch to Next Robot'),
    );
  }
}