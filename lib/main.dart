import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MyKasiSuKasiApp());
}

// === GLOBAL TRIP STATE - Shared Driver <-> Rider ===
String tripStatus =
    "none"; // none, requested, atPickup, inProgress, arrivedDest, paid, rated, unpaid
String tripPickupLabel = "";
String tripDestLabel = "";
String tripDriverName = "";
String tripDriverPlate = "";
String tripCarName = "";
String tripPaymentMethod = ""; // CASH, WALLET, UNPAID
double tripLockedPrice = 0.0;

// === PERSISTENCE HELPERS - FIXES CLOSE APP PROBLEM ===
Future<void> saveWallet(double amount) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setDouble('walletBalance', amount);
}

Future<double> loadWallet() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getDouble('walletBalance') ?? 0.0;
}

Future<void> saveBookings(List<String> list) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList('bookings', list);
}

Future<List<String>> loadBookings() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getStringList('bookings') ?? [];
}

Future<void> saveTripStatus(String s) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('tripStatus', s);
}

// === OWNER SETTINGS ===
const String OWNER_WHATSAPP = "27731234567";
const String OWNER_BANK_ACCOUNT = "1309906015";
const String OWNER_BANK_NAME = "Capitec";

Map<String, Map<String, dynamic>> DRIVER_ACCOUNTS = {
  "Mosiane@000": {
    "name": "Mosiane - OWNER",
    "plate": "OWNER-000",
    "phone": "",
    "isOwner": true,
    "verified": true,
    "rating": 5.0,
    "carRating": 5.0,
    "blocked": false,
    "trips": 45,
    "earned": 12450.0,
    "debt": 0.0
  },
  "Mosiane@1": {
    "name": "Driver 1",
    "plate": "",
    "phone": "",
    "isOwner": false,
    "verified": true,
    "rating": 4.8,
    "carRating": 4.7,
    "blocked": false,
    "trips": 12,
    "earned": 3200.0,
    "debt": 0.0
  },
  "Mosiane@2": {
    "name": "Driver 2",
    "plate": "",
    "phone": "",
    "isOwner": false,
    "verified": true,
    "rating": 4.6,
    "carRating": 4.5,
    "blocked": false,
    "trips": 8,
    "earned": 2100.0,
    "debt": 0.0
  },
  "Mosiane@3": {
    "name": "Driver 3",
    "plate": "",
    "phone": "",
    "isOwner": false,
    "verified": false,
    "rating": 0.0,
    "carRating": 0.0,
    "blocked": false,
    "trips": 0,
    "earned": 0.0,
    "debt": 0.0
  },
  "Mosiane@4": {
    "name": "Driver 4",
    "plate": "",
    "phone": "",
    "isOwner": false,
    "verified": false,
    "rating": 0.0,
    "carRating": 0.0,
    "blocked": false,
    "trips": 0,
    "earned": 0.0,
    "debt": 0.0
  },
  "Mosiane@5": {
    "name": "Driver 5",
    "plate": "",
    "phone": "",
    "isOwner": false,
    "verified": false,
    "rating": 0.0,
    "carRating": 0.0,
    "blocked": false,
    "trips": 0,
    "earned": 0.0,
    "debt": 0.0
  },
};
int nextDriverNum = 6;

Future<void> notifyOwnerOnWhatsApp(
    {required String driverCode,
    required String driverName,
    required String driverPlate,
    required String driverPhone,
    required double amount}) async {
  String driverNumber = driverCode.replaceAll("Mosiane@", "Driver ");
  String fullReference =
      "$driverCode - $driverNumber - $driverName - $driverPlate";
  String message =
      "CHECK DRIVER PAID - VERIFY IN CAPITEC\n-----------------------------\nDriver Name: $driverName\nDriver Code: $driverCode\nDriver Number: $driverNumber\nCar Plate: ${driverPlate.isEmpty ? 'No Plate' : driverPlate}\nPhone: ${driverPhone.isEmpty ? 'No Phone' : driverPhone}\nAmount Paid: R${amount.toStringAsFixed(0)}\nBank: $OWNER_BANK_NAME - $OWNER_BANK_ACCOUNT\nReference: $fullReference\n-----------------------------\nPlease check Capitec app if it truly reflected. If yes, go to Owner Panel and RELEASE him.";
  final Uri url = Uri.parse(
      "https://wa.me/$OWNER_WHATSAPP?text=${Uri.encodeComponent(message)}");
  if (await canLaunchUrl(url))
    await launchUrl(url, mode: LaunchMode.externalApplication);
}

Future<void> notifyOwnerTopUp(
    {required String riderName,
    required String riderPhone,
    required double amount}) async {
  String fullReference =
      "TOPUP - $riderName - $riderPhone - R${amount.toStringAsFixed(0)}";
  String message =
      "RIDER WANTS TO TOP UP WALLET\n-----------------------------\nRider Name: ${riderName.isEmpty ? 'Rider' : riderName}\nPhone: ${riderPhone.isEmpty ? 'No Phone' : riderPhone}\nTop Up Amount: R${amount.toStringAsFixed(0)}\nPay To Bank: $OWNER_BANK_NAME - $OWNER_BANK_ACCOUNT\nReference: $fullReference\n-----------------------------\nRider will pay in Capitec app. Owner please check Capitec and add to rider wallet in Owner Panel.";
  final Uri url = Uri.parse(
      "https://wa.me/$OWNER_WHATSAPP?text=${Uri.encodeComponent(message)}");
  if (await canLaunchUrl(url))
    await launchUrl(url, mode: LaunchMode.externalApplication);
}

class CarSpec {
  final String make;
  final String model;
  final String year;
  final String engine;
  final double consumption;
  final String fuelType;
  final int seats;
  CarSpec(this.make, this.model, this.year, this.engine, this.consumption,
      this.fuelType, this.seats);
  String get display => "$make $model $year $engine - ${consumption}L/100km";
}

List<CarSpec> CAR_DATABASE = [
  CarSpec("Toyota", "Corolla Quest 1.8 Plus Manual", "2023", "1.8L Petrol", 7.0,
      "Petrol", 5),
  CarSpec("Toyota", "Corolla Quest 1.8 XS Auto", "2022", "1.8L Petrol Auto",
      6.8, "Petrol", 5),
  CarSpec("Toyota", "Corolla Cross 1.8 XS", "2023", "1.8L Petrol", 6.5,
      "Petrol", 5),
  CarSpec("Toyota", "Starlet 1.4 XR", "2023", "1.4L Petrol", 5.5, "Petrol", 5),
  CarSpec("Suzuki", "Swift 1.2 GL", "2023", "1.2L Petrol", 5.0, "Petrol", 5),
  CarSpec("Hyundai", "Grand i10 1.2 Motion", "2023", "1.2L Petrol", 5.8,
      "Petrol", 5),
  CarSpec("Volkswagen", "Polo Vivo 1.4 Comfortline", "2023", "1.4L Petrol", 6.2,
      "Petrol", 5),
  CarSpec("Kia", "Picanto 1.2 Smart", "2023", "1.2L Petrol", 5.4, "Petrol", 5),
  CarSpec("Nissan", "Almera 1.5", "2023", "1.5L Petrol", 6.0, "Petrol", 5),
  CarSpec("Renault", "Kwid 1.0", "2023", "1.0L Petrol", 4.7, "Petrol", 5),
];

class TripRecord {
  String pickup;
  String dest;
  String date;
  String carName;
  double price;
  int rating;
  int carRating;
  String paymentMethod;
  bool isReturn;
  bool isScheduled;
  TripRecord(this.pickup, this.dest, this.date, this.carName, this.price,
      {this.rating = 0,
      this.carRating = 0,
      this.paymentMethod = "CASH",
      this.isReturn = false,
      this.isScheduled = false});
}

List<TripRecord> tripHistory = [
  TripRecord("Garankuwa", "Mafikeng", "22 Oct 2026", "Corolla Quest", 450,
      rating: 5, carRating: 5, paymentMethod: "CASH"),
  TripRecord("Pretoria", "Rustenburg", "20 Oct 2026", "Swift", 320,
      rating: 4, carRating: 4, paymentMethod: "WALLET"),
];

class MyKasiSuKasiApp extends StatelessWidget {
  const MyKasiSuKasiApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'MyKasiSuKasi',
        theme: ThemeData(
            primaryColor: const Color(0xFF0B4F5C),
            scaffoldBackgroundColor: const Color(0xFFF5F5F5)),
        home: const RoleSelectPage());
  }
}

class RoleSelectPage extends StatefulWidget {
  const RoleSelectPage({super.key});
  @override
  State<RoleSelectPage> createState() => _RoleSelectPageState();
}

class _RoleSelectPageState extends State<RoleSelectPage> {
  final codeCtrl = TextEditingController();
  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final plateCtrl = TextEditingController();
  String error = "";
  void tryDriverLogin() {
    String code = codeCtrl.text.trim();
    if (DRIVER_ACCOUNTS.containsKey(code)) {
      var acc = DRIVER_ACCOUNTS[code]!;
      if (acc['blocked'] == true) {
        setState(() => error = "This driver account is blocked by owner.");
        return;
      }
      String driverName =
          nameCtrl.text.isNotEmpty ? nameCtrl.text : acc['name'];
      String driverPlate =
          plateCtrl.text.isNotEmpty ? plateCtrl.text : acc['plate'];
      String driverPhone = phoneCtrl.text;
      acc['name'] = driverName;
      acc['plate'] = driverPlate;
      acc['phone'] = driverPhone;
      bool isOwner = acc['isOwner'] == true;
      if (isOwner) {
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    AdminPanelPage(ownerName: driverName, ownerCode: code)));
      } else {
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => DriverCarPage(
                    driverCode: code,
                    driverName: driverName,
                    driverPlate: driverPlate,
                    driverPhone: driverPhone)));
      }
    } else {
      setState(() => error = "Access denied. Contact owner.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              const SizedBox(height: 40),
              const Icon(Icons.home, size: 80, color: Color(0xFFFF7A00)),
              const Text("MyKasiSuKasi",
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const Text("Ride Kasi, Travel Far",
                  style: TextStyle(
                      color: Color(0xFFFF7A00), fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              const Text("Who Are You?",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                      onPressed: () => Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const HomePage(isDriver: false))),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0B4F5C),
                          padding: const EdgeInsets.all(16)),
                      child: const Text("I AM A RIDER - I Need A Ride",
                          style: TextStyle(fontSize: 16)))),
              const SizedBox(height: 20),
              const Divider(),
              const Text("DRIVER LOGIN",
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.red)),
              const Text("Drivers only - Contact owner for access",
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 12),
              TextField(
                  controller: codeCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: "Enter Driver Code",
                      hintText: "********",
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.lock))),
              const SizedBox(height: 10),
              TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                      labelText: "Your Full Names",
                      hintText: "e.g. Thabo Mosiane",
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person))),
              const SizedBox(height: 10),
              TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(
                      labelText: "Your Phone",
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.phone))),
              const SizedBox(height: 10),
              TextField(
                  controller: plateCtrl,
                  decoration: const InputDecoration(
                      labelText: "Car Plate",
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.directions_car))),
              if (error.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(error,
                        style: const TextStyle(
                            color: Colors.red, fontWeight: FontWeight.bold))),
              const SizedBox(height: 10),
              SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                      onPressed: tryDriverLogin,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF7A00),
                          padding: const EdgeInsets.all(16)),
                      child: const Text("LOGIN AS DRIVER"))),
            ])));
  }
}

class DriverCarPage extends StatefulWidget {
  final String driverCode;
  final String driverName;
  final String driverPlate;
  final String driverPhone;
  const DriverCarPage(
      {super.key,
      required this.driverCode,
      required this.driverName,
      required this.driverPlate,
      required this.driverPhone});
  @override
  State<DriverCarPage> createState() => _DriverCarPageState();
}

class _DriverCarPageState extends State<DriverCarPage> {
  CarSpec? selectedSpec;
  final makeCtrl = TextEditingController();
  final modelCtrl = TextEditingController();
  final yearCtrl = TextEditingController(text: "2023");
  final engineCtrl = TextEditingController();
  final consCtrl = TextEditingController();
  final plateCtrl = TextEditingController();
  List<CarSpec> filtered = CAR_DATABASE;
  @override
  void initState() {
    super.initState();
    plateCtrl.text = widget.driverPlate;
  }

  void filterCars(String q) {
    setState(() {
      if (q.isEmpty) {
        filtered = CAR_DATABASE;
      } else {
        filtered = CAR_DATABASE
            .where((c) => c.display.toLowerCase().contains(q.toLowerCase()))
            .toList();
      }
    });
  }

  void selectCar(CarSpec spec) {
    setState(() {
      selectedSpec = spec;
      makeCtrl.text = spec.make;
      modelCtrl.text = spec.model;
      yearCtrl.text = spec.year;
      engineCtrl.text = spec.engine;
      consCtrl.text = spec.consumption.toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
            title: const Text("Your Car"), backgroundColor: Colors.green[800]),
        body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("Step 2: Enter Your Car Details",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Text(
                  "Search your exact car - fuel auto-filled. If not listed, type it below.",
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 12),
              TextField(
                  decoration: const InputDecoration(
                      labelText: "Search Car e.g. Corolla Quest, Swift",
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder()),
                  onChanged: filterCars),
              const SizedBox(height: 12),
              Container(
                  height: 220,
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300)),
                  child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) {
                        CarSpec c = filtered[i];
                        bool isSel = selectedSpec == c;
                        return ListTile(
                            title: Text(c.display,
                                style: TextStyle(
                                    fontWeight: isSel
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    fontSize: 13)),
                            subtitle: Text("${c.engine} - ${c.fuelType}"),
                            onTap: () => selectCar(c),
                            trailing: isSel
                                ? const Icon(Icons.check_circle,
                                    color: Colors.green)
                                : null);
                      })),
              const SizedBox(height: 16),
              const Text("If your car is NOT in the list - Add it here:",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                  controller: makeCtrl,
                  decoration: const InputDecoration(
                      labelText: "Car Make", border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(
                  controller: modelCtrl,
                  decoration: const InputDecoration(
                      labelText: "Car Model", border: OutlineInputBorder())),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: yearCtrl,
                        decoration: const InputDecoration(
                            labelText: "Year", border: OutlineInputBorder()))),
                const SizedBox(width: 8),
                Expanded(
                    child: TextField(
                        controller: engineCtrl,
                        decoration: const InputDecoration(
                            labelText: "Engine", border: OutlineInputBorder())))
              ]),
              const SizedBox(height: 8),
              TextField(
                  controller: plateCtrl,
                  decoration: const InputDecoration(
                      labelText: "Number Plate", border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(
                  controller: consCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: "Fuel Consumption L/100km",
                      border: OutlineInputBorder(),
                      suffixText: "L/100km")),
              const SizedBox(height: 16),
              SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                      onPressed: () {
                        double cons = double.tryParse(consCtrl.text) ?? 6.5;
                        CarSpec myCar = CarSpec(
                            makeCtrl.text.isEmpty ? "Toyota" : makeCtrl.text,
                            modelCtrl.text.isEmpty
                                ? "Corolla Quest"
                                : modelCtrl.text,
                            yearCtrl.text,
                            engineCtrl.text.isEmpty ? "1.8L" : engineCtrl.text,
                            cons,
                            "Petrol",
                            5);
                        if (!CAR_DATABASE.contains(myCar))
                          CAR_DATABASE.add(myCar);
                        Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                                builder: (_) => HomePage(
                                    isDriver: true,
                                    driverName: widget.driverName,
                                    driverPlate: plateCtrl.text,
                                    driverCode: widget.driverCode,
                                    driverPhone: widget.driverPhone,
                                    myCar: myCar)));
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF7A00),
                          padding: const EdgeInsets.all(16)),
                      child: const Text("SAVE MY CAR - GO TO DRIVER MODE"))),
            ])));
  }
}

class AdminPanelPage extends StatefulWidget {
  final String ownerName;
  final String ownerCode;
  const AdminPanelPage(
      {super.key, required this.ownerName, required this.ownerCode});
  @override
  State<AdminPanelPage> createState() => _AdminPanelPageState();
}

class _AdminPanelPageState extends State<AdminPanelPage> {
  @override
  Widget build(BuildContext context) {
    double totalEarned = 0;
    int totalTrips = 0;
    double totalDebt = 0;
    for (var v in DRIVER_ACCOUNTS.values) {
      totalEarned += (v['earned'] as double);
      totalTrips += (v['trips'] as int);
      totalDebt += (v['debt'] as double);
    }
    return Scaffold(
        appBar: AppBar(
            title: const Text("OWNER PANEL"), backgroundColor: Colors.black),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.black, borderRadius: BorderRadius.circular(16)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("WELCOME OWNER",
                        style: TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                            fontSize: 18)),
                    Text("Name: ${widget.ownerName}",
                        style: const TextStyle(color: Colors.white)),
                    const Text("You control all drivers + riders",
                        style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 8),
                    const Text(
                        "Your Bank: Capitec 1309906015 - Check with driver reference",
                        style: TextStyle(
                            color: Colors.orange,
                            fontSize: 12,
                            fontWeight: FontWeight.bold))
                  ])),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _stat("TOTAL TRIPS", "$totalTrips")),
            const SizedBox(width: 8),
            Expanded(
                child: _stat(
                    "TOTAL EARNED", "R${totalEarned.toStringAsFixed(0)}")),
            const SizedBox(width: 8),
            Expanded(
                child: _stat(
                    "TOTAL OWED TO YOU", "R${totalDebt.toStringAsFixed(0)}"))
          ]),
          const SizedBox(height: 16),
          SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => HomePage(
                              isDriver: true,
                              driverName: widget.ownerName,
                              driverPlate: "OWNER-000",
                              driverCode: widget.ownerCode,
                              isOwner: true,
                              myCar: CAR_DATABASE[0]))),
                  icon: const Icon(Icons.directions_car),
                  label: const Text("GO TO DRIVER SECTION"),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[800],
                      padding: const EdgeInsets.all(14)))),
          const SizedBox(height: 10),
          SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const HomePage(
                              isDriver: false, isOwnerView: true))),
                  icon: const Icon(Icons.person),
                  label: const Text("GO TO RIDER SECTION"),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0B4F5C),
                      padding: const EdgeInsets.all(14)))),
          const SizedBox(height: 16),
          Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Add New Driver From App",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const Text("Creates next driver automatically",
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 8),
                    ElevatedButton(
                        onPressed: () {
                          setState(() {
                            String newCode = "Mosiane@$nextDriverNum";
                            DRIVER_ACCOUNTS[newCode] = {
                              "name": "Driver $nextDriverNum - New",
                              "plate": "",
                              "phone": "",
                              "isOwner": false,
                              "verified": false,
                              "rating": 0.0,
                              "carRating": 0.0,
                              "blocked": false,
                              "trips": 0,
                              "earned": 0.0,
                              "debt": 0.0
                            };
                            nextDriverNum++;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text(
                                  "New driver created! Tell him his code in person.")));
                        },
                        child: const Text("CREATE NEW DRIVER"))
                  ])),
          const SizedBox(height: 16),
          const Text("Your Drivers - Block / Verify / Debt / Release",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...DRIVER_ACCOUNTS.entries.map((e) {
            bool isOwner = e.value['isOwner'] == true;
            bool blocked = e.value['blocked'] == true;
            bool verified = e.value['verified'] == true;
            double debt = (e.value['debt'] as double);
            return Card(
                child: ListTile(
                    leading: Icon(
                        isOwner ? Icons.admin_panel_settings : Icons.person,
                        color: isOwner ? Colors.black : Colors.orange),
                    title: Row(children: [
                      Text(isOwner ? "OWNER" : e.value['name'],
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 6),
                      if (verified)
                        const Icon(Icons.verified,
                            color: Colors.green, size: 18),
                      if (blocked)
                        const Text(" BLOCKED",
                            style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 11)),
                      if (debt >= 100)
                        const Text(" R100 DEBT",
                            style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 11))
                    ]),
                    subtitle: Text(
                        "Code: ${e.key} - Plate: ${e.value['plate']} - Driver: ${e.value['rating']}★ - Car: ${e.value['carRating']}★ - Trips: ${e.value['trips']} - Earned: R${e.value['earned']} - Owes: R${debt.toStringAsFixed(0)}"),
                    trailing: isOwner
                        ? const Text("YOU",
                            style: TextStyle(
                                color: Colors.red, fontWeight: FontWeight.bold))
                        : Column(mainAxisSize: MainAxisSize.min, children: [
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                  icon: Icon(
                                      verified
                                          ? Icons.verified
                                          : Icons.verified_outlined,
                                      color: Colors.green,
                                      size: 20),
                                  onPressed: () => setState(
                                      () => e.value['verified'] = !verified)),
                              IconButton(
                                  icon: Icon(
                                      blocked ? Icons.lock_open : Icons.block,
                                      color: Colors.red,
                                      size: 20),
                                  onPressed: () => setState(
                                      () => e.value['blocked'] = !blocked))
                            ]),
                            if (debt >= 100)
                              ElevatedButton(
                                  onPressed: () =>
                                      setState(() => e.value['debt'] = 0.0),
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2)),
                                  child: const Text("RELEASE",
                                      style: TextStyle(fontSize: 10)))
                            else if (debt > 0)
                              TextButton(
                                  onPressed: () =>
                                      setState(() => e.value['debt'] = 0.0),
                                  child: const Text("Paid",
                                      style: TextStyle(
                                          fontSize: 11, color: Colors.green)))
                          ])));
          }),
          const SizedBox(height: 16),
          const Text("Trip History (All Drivers)",
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...tripHistory.map((t) => Card(
              child: ListTile(
                  title: Text("${t.pickup} -> ${t.dest}"),
                  subtitle: Text(
                      "${t.date} - ${t.carName} - R${t.price} - ${t.paymentMethod} - Driver ${t.rating}★ - Car ${t.carRating}★"),
                  trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(
                          5,
                          (i) => Icon(Icons.star,
                              size: 14,
                              color: i < t.rating
                                  ? Colors.amber
                                  : Colors.grey)))))),
          const SizedBox(height: 16),
          SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                  onPressed: () => Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const RoleSelectPage())),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                  child: const Text("LOGOUT"))),
        ]));
  }

  Widget _stat(String label, String value) {
    return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey))
        ]));
  }
}

class HomePage extends StatefulWidget {
  final bool isDriver;
  final String? driverName;
  final String? driverPlate;
  final String? driverCode;
  final String? driverPhone;
  final bool isOwner;
  final bool isOwnerView;
  final CarSpec? myCar;
  const HomePage(
      {super.key,
      this.isDriver = false,
      this.driverName,
      this.driverPlate,
      this.driverCode,
      this.driverPhone,
      this.isOwner = false,
      this.isOwnerView = false,
      this.myCar});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  CarSpec? selectedCar;
  final pickupCtrl = TextEditingController(text: "Garankuwa, Pretoria");
  final dropCtrl = TextEditingController(text: "Mafikeng");
  final kmCtrl = TextEditingController(text: "323");
  final riderNameCtrl = TextEditingController();
  final riderPhoneCtrl = TextEditingController();
  double petrolPrice = 30.25;
  int passengers = 4;
  int currentIndex = 0;
  double walletBalance = 0.0;
  List<String> bookings = [];
  ll.LatLng? pickupLatLng;
  ll.LatLng? dropLatLng;
  double tolls = 173;
  double estHours = 3.5;
  bool isReturnTrip = false;
  bool isScheduled = false;
  bool priceLocked = false;
  double lockedPrice = 0;
  ll.LatLng driverLivePos = ll.LatLng(-25.65, 27.9);

  @override
  void initState() {
    super.initState();
    selectedCar = widget.myCar ?? CAR_DATABASE[0];
    pickupLatLng = ll.LatLng(-25.6038, 28.0880);
    dropLatLng = ll.LatLng(-25.8653, 25.6447);
    updateRouteInfo();
    _loadSavedData();
  }

  Future<void> _loadSavedData() async {
    double w = await loadWallet();
    List<String> b = await loadBookings();
    setState(() {
      walletBalance = w;
      bookings = b;
    });
  }

  void updateRouteInfo() {
    double k = double.tryParse(kmCtrl.text) ?? 323;
    if (k > 300) {
      tolls = 173;
      estHours = k / 90;
    } else if (k > 200) {
      tolls = 100;
      estHours = k / 85;
    } else if (k > 100) {
      tolls = 50;
      estHours = k / 80;
    } else {
      tolls = 0;
      estHours = k / 70;
    }
  }

  Future<void> openInGoogleMaps() async {
    final Uri url = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&origin=${Uri.encodeComponent(pickupCtrl.text)}&destination=${Uri.encodeComponent(dropCtrl.text)}&travelmode=driving');
    if (await canLaunchUrl(url))
      await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> pickLocation(bool isPickup) async {
    final result = await Navigator.push<Map<String, dynamic>>(context,
        MaterialPageRoute(builder: (_) => MapPickerPage(isPickup: isPickup)));
    if (result != null) {
      ll.LatLng pos = result['pos'];
      String name = result['name'] ?? "Pinned Location";
      setState(() {
        if (isPickup) {
          pickupLatLng = pos;
          pickupCtrl.text = name;
        } else {
          dropLatLng = pos;
          dropCtrl.text = name;
        }
        if (pickupLatLng != null && dropLatLng != null) {
          double straight = Geolocator.distanceBetween(
                  pickupLatLng!.latitude,
                  pickupLatLng!.longitude,
                  dropLatLng!.latitude,
                  dropLatLng!.longitude) /
              1000;
          kmCtrl.text = (straight * 1.35).toStringAsFixed(0);
          updateRouteInfo();
        }
      });
    }
  }

  void shareWhatsApp() async {
    String msg =
        "MyKasiSuKasi Trip: ${pickupCtrl.text} -> ${dropCtrl.text} - ${km}km - R${pricePerPerson.toStringAsFixed(0)} per person";
    final Uri url =
        Uri.parse("https://wa.me/?text=${Uri.encodeComponent(msg)}");
    if (await canLaunchUrl(url))
      await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  double get km => double.tryParse(kmCtrl.text) ?? 323;
  double get litres => km * selectedCar!.consumption / 100;
  double get petrolCost => litres * petrolPrice;
  double get totalCost => petrolCost + tolls;
  double get pricePerPerson =>
      (totalCost + 983) / 4 * (isReturnTrip ? 0.9 : 1.0);
  double get totalIncome => pricePerPerson * passengers;
  double get profit => totalIncome - totalCost;
  int get etaMinutes => (estHours * 60).toInt();

  void bookRide() async {
    setState(() {
      priceLocked = true;
      lockedPrice = pricePerPerson;
      bookings.add(
          "${pickupCtrl.text} -> ${dropCtrl.text} - LOCKED R${lockedPrice.toStringAsFixed(0)}");
      tripHistory.insert(
          0,
          TripRecord(pickupCtrl.text, dropCtrl.text, "Today",
              selectedCar!.display, lockedPrice,
              isReturn: isReturnTrip, isScheduled: isScheduled));
      // NO WALLET DEDUCT HERE - Only when driver confirms PAID
      tripStatus = "requested";
      tripPickupLabel = pickupCtrl.text;
      tripDestLabel = dropCtrl.text;
      tripLockedPrice = lockedPrice;
      tripDriverName = "Driver 1 - Thabo";
      tripCarName = selectedCar!.display;
      tripDriverPlate = "JHD 456 GP";
    });
    await saveBookings(bookings);
    await saveTripStatus(tripStatus);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            "Booking Locked! R${lockedPrice.toStringAsFixed(0)} - Wallet will only be deducted after driver confirms RIDER PAID")));
  }

  void showRatingDialog() {
    int driverStars = 5;
    int carStars = 5;
    final commentCtrl = TextEditingController();
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx2, setS) => AlertDialog(
                  title: const Text("Trip Completed! Rate Your Trip"),
                  content: SingleChildScrollView(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(
                            "Payment: $tripPaymentMethod - R${tripLockedPrice.toStringAsFixed(0)}",
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green)),
                        const SizedBox(height: 6),
                        const Text("Did you arrive at destination?",
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                        Text("$tripPickupLabel -> $tripDestLabel",
                            style: const TextStyle(fontSize: 12)),
                        const Divider(),
                        Text("Driver: $tripDriverName",
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        Row(
                            children: List.generate(
                                5,
                                (i) => IconButton(
                                    icon: Icon(Icons.star,
                                        color: i < driverStars
                                            ? Colors.amber
                                            : Colors.grey),
                                    onPressed: () =>
                                        setS(() => driverStars = i + 1)))),
                        Text("Car: $tripCarName - Plate $tripDriverPlate",
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                        Row(
                            children: List.generate(
                                5,
                                (i) => IconButton(
                                    icon: Icon(Icons.star,
                                        color: i < carStars
                                            ? Colors.amber
                                            : Colors.grey),
                                    onPressed: () =>
                                        setS(() => carStars = i + 1)))),
                        const Text("Was car clean? Comfortable?"),
                        const SizedBox(height: 8),
                        TextField(
                            controller: commentCtrl,
                            decoration: const InputDecoration(
                                labelText: "Comment (optional)",
                                border: OutlineInputBorder())),
                      ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text("Not Arrived Yet")),
                    ElevatedButton(
                        onPressed: () async {
                          setState(() {
                            tripStatus = "rated";
                            if (DRIVER_ACCOUNTS.containsKey("Mosiane@1")) {
                              var acc = DRIVER_ACCOUNTS["Mosiane@1"]!;
                              double old = acc['rating'];
                              acc['rating'] =
                                  ((old + driverStars) / 2).clamp(1.0, 5.0);
                              double oldCar = acc['carRating'];
                              acc['carRating'] =
                                  ((oldCar + carStars) / 2).clamp(1.0, 5.0);
                            }
                            if (tripHistory.isNotEmpty) {
                              tripHistory[0].rating = driverStars;
                              tripHistory[0].carRating = carStars;
                              tripHistory[0].paymentMethod = tripPaymentMethod;
                            }
                          });
                          await saveTripStatus("rated");
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(
                                  "Thank you! Driver rated $driverStars★ - Car rated $carStars★")));
                        },
                        child: const Text("SUBMIT RATING"),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green)),
                  ],
                )));
  }

  void showTopUpDialog() {
    final amountCtrl = TextEditingController(text: "500");
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text("Top Up Wallet via Capitec"),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text("1. Pay to Capitec 1309906015",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const Text("2. Use reference: TOPUP - Your Name - Your Phone",
                    style: TextStyle(fontSize: 12)),
                const SizedBox(height: 12),
                TextField(
                    controller: riderNameCtrl,
                    decoration: const InputDecoration(
                        labelText: "Your Full Names",
                        border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(
                    controller: riderPhoneCtrl,
                    decoration: const InputDecoration(
                        labelText: "Your Phone", border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: "Amount to Top Up R",
                        border: OutlineInputBorder())),
                const SizedBox(height: 8),
                Row(children: [
                  for (var a in ["100", "200", "500", "1000"])
                    Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ElevatedButton(
                            onPressed: () => amountCtrl.text = a,
                            child: Text("R$a")))
                ]),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("Cancel")),
                ElevatedButton(
                    onPressed: () async {
                      double amt = double.tryParse(amountCtrl.text) ?? 500;
                      Navigator.pop(ctx);
                      await notifyOwnerTopUp(
                          riderName: riderNameCtrl.text,
                          riderPhone: riderPhoneCtrl.text,
                          amount: amt);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text(
                              "WhatsApp opened! Pay in Capitec, then tap SEND. Owner will add money to your wallet after checking Capitec.")));
                    },
                    child: const Text("WHATSAPP OWNER")),
              ],
            ));
  }

  Widget tripStatusBanner() {
    if (tripStatus == "none") return const SizedBox();
    String text = "";
    Color col = Colors.orange;
    if (tripStatus == "requested") {
      text = "● Driver accepted - On his way to PICKUP: $tripPickupLabel";
      col = Colors.orange;
    }
    if (tripStatus == "atPickup") {
      text =
          "● DRIVER HAS ARRIVED AT PICKUP! Go outside - $tripDriverName is waiting - Plate $tripDriverPlate";
      col = Colors.green;
    }
    if (tripStatus == "inProgress") {
      text =
          "● TRIP IN PROGRESS - Heading to $tripDestLabel - ETA $etaMinutes min";
      col = Colors.blue;
    }
    if (tripStatus == "arrivedDest") {
      text =
          "● DRIVER SAYS: I HAVE ARRIVED AT DESTINATION - Waiting for driver to confirm payment";
      col = Colors.purple;
    }
    if (tripStatus == "paid") {
      text =
          "● PAYMENT CONFIRMED: $tripPaymentMethod - R${tripLockedPrice.toStringAsFixed(0)} - Please confirm arrival & rate";
      col = Colors.teal;
    }
    if (tripStatus == "unpaid") {
      text = "⚠ DRIVER REPORTED: RIDER DID NOT PAY - Owner notified";
      col = Colors.red;
    }
    if (tripStatus == "rated") {
      text = "✓ Trip completed & rated. Thank you!";
      col = Colors.green;
    }
    return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 12),
        decoration:
            BoxDecoration(color: col, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13)),
          if (tripStatus == "atPickup")
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ElevatedButton(
                    onPressed: () => setState(() {
                          tripStatus = "inProgress";
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text(
                                  "Confirmed: Driver picked you up - Trip started")));
                        }),
                    child: const Text("CONFIRM: I AM IN THE CAR - START TRIP"),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.green))),
          if (tripStatus == "paid")
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ElevatedButton(
                    onPressed: showRatingDialog,
                    child: const Text("YES I ARRIVED - RATE DRIVER & CAR"),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.teal))),
          if (tripStatus == "requested")
            Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                    "Driver location: Live map below - He will tap 'Arrived at Pickup' when he is outside",
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.9), fontSize: 11))),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isDriver) {
      Map<String, dynamic>? acc =
          widget.driverCode != null ? DRIVER_ACCOUNTS[widget.driverCode] : null;
      double debt = acc != null ? (acc['debt'] as double) : 0;
      bool canAccept = debt < 100;
      double earned = acc != null ? (acc['earned'] as double) : 0;
      int trips = acc != null ? (acc['trips'] as int) : 0;
      String fullName =
          acc != null ? acc['name'] : widget.driverName ?? "Driver";
      String plate = widget.driverPlate ?? (acc?['plate'] ?? "");
      String phone = widget.driverPhone ?? (acc?['phone'] ?? "");
      String driverNumberLabel =
          (widget.driverCode ?? "").replaceAll("Mosiane@", "Driver ");
      String fullReference =
          "${widget.driverCode} - $driverNumberLabel - $fullName - $plate";
      return Scaffold(
          appBar: AppBar(
              title: Text(
                  widget.isOwner ? "OWNER - DRIVER SECTION" : "DRIVER MODE"),
              backgroundColor:
                  widget.isOwner ? Colors.black : Colors.green[800]),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: widget.isOwner ? Colors.black : Colors.green[50],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.green)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(
                            widget.isOwner
                                ? "OWNER ACCOUNT"
                                : "VERIFIED DRIVER",
                            style: TextStyle(
                                color: widget.isOwner
                                    ? Colors.orange
                                    : Colors.green,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(width: 6),
                        const Icon(Icons.verified, color: Colors.green)
                      ]),
                      Text("Name: $fullName",
                          style: TextStyle(
                              color: widget.isOwner
                                  ? Colors.white
                                  : Colors.black)),
                      Text("Code: ${widget.driverCode}",
                          style: TextStyle(
                              color: widget.isOwner
                                  ? Colors.white
                                  : Colors.black)),
                      Text("Plate: $plate",
                          style: TextStyle(
                              color: widget.isOwner
                                  ? Colors.white
                                  : Colors.black)),
                      if (widget.myCar != null)
                        Text("Car: ${widget.myCar!.display}",
                            style: TextStyle(
                                color: widget.isOwner
                                    ? Colors.white
                                    : Colors.black,
                                fontWeight: FontWeight.bold)),
                      if (widget.myCar != null)
                        Text("Fuel: ${widget.myCar!.consumption} L/100km",
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey))
                    ])),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12)),
                      child: Column(children: [
                        const Text("TRIPS",
                            style: TextStyle(fontSize: 11, color: Colors.grey)),
                        Text("$trips",
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 18))
                      ]))),
              const SizedBox(width: 8),
              Expanded(
                  child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12)),
                      child: Column(children: [
                        const Text("EARNED",
                            style: TextStyle(fontSize: 11, color: Colors.grey)),
                        Text("R${earned.toStringAsFixed(0)}",
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: Colors.green))
                      ]))),
              const SizedBox(width: 8),
              Expanded(
                  child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12)),
                      child: Column(children: [
                        const Text("PROFIT",
                            style: TextStyle(fontSize: 11, color: Colors.grey)),
                        Text("R${profit.toStringAsFixed(0)}",
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 18))
                      ])))
            ]),
            const SizedBox(height: 12),
            Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: debt >= 100 ? Colors.red[50] : Colors.orange[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: debt >= 100 ? Colors.red : Colors.orange)),
                child: Column(children: [
                  Row(children: [
                    Icon(Icons.warning,
                        color: debt >= 100 ? Colors.red : Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(
                            "You owe owner: R${debt.toStringAsFixed(0)} / R100",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color:
                                    debt >= 100 ? Colors.red : Colors.black))),
                    Text(
                        debt >= 100
                            ? "BLOCKED"
                            : "${(100 - debt).toStringAsFixed(0)} left",
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey))
                  ]),
                  if (debt >= 100) ...[
                    const SizedBox(height: 12),
                    Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8)),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("PAY TO GET RELEASED",
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red)),
                              const SizedBox(height: 6),
                              Text("Bank: $OWNER_BANK_NAME"),
                              Text("Account: $OWNER_BANK_ACCOUNT"),
                              const Text("Amount: R100"),
                              Text(
                                  "Reference to use in Capitec: $fullReference",
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red)),
                              const SizedBox(height: 8),
                              const Text(
                                  "1. Pay in your Capitec app with the reference above",
                                  style: TextStyle(fontSize: 12)),
                              const Text(
                                  "2. Tap NOTIFY OWNER below - WhatsApp will open",
                                  style: TextStyle(fontSize: 12)),
                              const Text("3. Tap SEND in WhatsApp",
                                  style: TextStyle(fontSize: 12))
                            ])),
                    const SizedBox(height: 8),
                    SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                            onPressed: () async {
                              await notifyOwnerOnWhatsApp(
                                  driverCode: widget.driverCode ?? "Unknown",
                                  driverName: fullName,
                                  driverPlate: plate,
                                  driverPhone: phone,
                                  amount: 100);
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          "WhatsApp opened! Tap SEND to notify owner. Owner will check Capitec and release you.")));
                            },
                            icon: const Icon(Icons.message),
                            label: const Text(
                                "I PAID R100 - NOTIFY OWNER ON WHATSAPP"),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                padding: const EdgeInsets.all(14)))),
                  ],
                  if (debt > 0 && debt < 100)
                    TextButton.icon(
                        onPressed: () async {
                          await notifyOwnerOnWhatsApp(
                              driverCode: widget.driverCode ?? "",
                              driverName: fullName,
                              driverPlate: plate,
                              driverPhone: phone,
                              amount: debt);
                        },
                        icon: const Icon(Icons.message, color: Colors.green),
                        label: Text(
                            "Pay R${debt.toStringAsFixed(0)} early? Notify owner on WhatsApp",
                            style: const TextStyle(color: Colors.green))),
                ])),
            if (!canAccept)
              const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(
                      "You owe R100. You cannot confirm rides until Owner releases you. Pay owner in person.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.red, fontWeight: FontWeight.bold))),
            const SizedBox(height: 16),
            Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("YOUR CURRENT TRIP",
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text("Status: $tripStatus",
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                      if (tripStatus != "none" && tripStatus != "rated")
                        Text("Pickup: $tripPickupLabel -> $tripDestLabel",
                            style: const TextStyle(fontSize: 13)),
                      const SizedBox(height: 10),
                      if (tripStatus == "requested")
                        SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                                onPressed: () => setState(() {
                                      tripStatus = "atPickup";
                                      tripDriverName = fullName;
                                      tripDriverPlate = plate;
                                      tripCarName =
                                          widget.myCar?.display ?? "Car";
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                              content: Text(
                                                  "You tapped: I HAVE ARRIVED AT PICKUP - Rider notified!")));
                                    }),
                                icon: const Icon(Icons.location_on),
                                label:
                                    const Text("1. I HAVE ARRIVED AT PICKUP"),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    padding: const EdgeInsets.all(14)))),
                      if (tripStatus == "atPickup")
                        SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                                onPressed: () => setState(() {
                                      tripStatus = "inProgress";
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                              content: Text(
                                                  "Trip started - Driving to destination")));
                                    }),
                                icon: const Icon(Icons.play_arrow),
                                label: const Text(
                                    "2. START TRIP - RIDER IS IN CAR"),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    padding: const EdgeInsets.all(14)))),
                      if (tripStatus == "inProgress")
                        SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                                onPressed: () => setState(() {
                                      tripStatus = "arrivedDest";
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                              content: Text(
                                                  "You tapped: ARRIVED AT DESTINATION - Now confirm payment")));
                                    }),
                                icon: const Icon(Icons.flag),
                                label: const Text(
                                    "3. I HAVE ARRIVED AT DESTINATION"),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.purple,
                                    padding: const EdgeInsets.all(14)))),
                      if (tripStatus == "arrivedDest")
                        Column(children: [
                          const Text("RIDER PAYMENT - Tap what happened:",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.purple)),
                          const SizedBox(height: 8),
                          SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                  onPressed: () async {
                                    setState(() {
                                      tripStatus = "paid";
                                      tripPaymentMethod = "CASH";
                                      if (acc != null) {
                                        acc['earned'] =
                                            (acc['earned'] as double) +
                                                tripLockedPrice;
                                      }
                                      if (tripHistory.isNotEmpty)
                                        tripHistory[0].paymentMethod = "CASH";
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                            content: Text(
                                                "Confirmed: RIDER PAID CASH R${tripLockedPrice.toStringAsFixed(0)}")));
                                  },
                                  icon: const Icon(Icons.money),
                                  label: Text(
                                      "RIDER PAID - CASH R${tripLockedPrice.toStringAsFixed(0)}"),
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      padding: const EdgeInsets.all(12)))),
                          const SizedBox(height: 8),
                          SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                  onPressed: () async {
                                    setState(() {
                                      tripStatus = "paid";
                                      tripPaymentMethod = "WALLET";
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                            content: Text(
                                                "Confirmed: RIDER PAID VIA WALLET R${tripLockedPrice.toStringAsFixed(0)} - Wallet will be deducted")));
                                  },
                                  icon:
                                      const Icon(Icons.account_balance_wallet),
                                  label: Text(
                                      "RIDER PAID - WALLET R${tripLockedPrice.toStringAsFixed(0)}"),
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.teal,
                                      padding: const EdgeInsets.all(12)))),
                          const SizedBox(height: 8),
                          SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                  onPressed: () => setState(() {
                                        tripStatus = "unpaid";
                                        tripPaymentMethod = "UNPAID";
                                        if (tripHistory.isNotEmpty)
                                          tripHistory[0].paymentMethod =
                                              "UNPAID";
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(const SnackBar(
                                                content: Text(
                                                    "Reported: RIDER DID NOT PAY - Owner will see this in history")));
                                      }),
                                  icon: const Icon(Icons.warning),
                                  label: const Text("RIDER DID NOT PAY"),
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      padding: const EdgeInsets.all(12)))),
                        ]),
                      if (tripStatus == "paid")
                        Text(
                            "✓ You confirmed $tripPaymentMethod paid - Rider can now rate you",
                            style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold)),
                      if (tripStatus == "unpaid")
                        const Text("⚠ Reported unpaid - Owner notified",
                            style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold)),
                      if (tripStatus == "rated")
                        const Text(
                            "✓ Trip completed & rated by rider. Well done!",
                            style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold)),
                      if (tripStatus == "none")
                        const Text(
                            "No active trip. Accept a ride below to start.",
                            style: TextStyle(fontSize: 12)),
                    ])),
            const SizedBox(height: 16),
            if (widget.isOwner)
              Row(children: [
                Expanded(
                    child: ElevatedButton(
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const HomePage(
                                    isDriver: false, isOwnerView: true))),
                        child: const Text("VIEW AS RIDER"))),
                const SizedBox(width: 8),
                Expanded(
                    child: ElevatedButton(
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => AdminPanelPage(
                                    ownerName: widget.driverName ?? "Owner",
                                    ownerCode: widget.driverCode ?? ""))),
                        child: const Text("OWNER PANEL")))
              ]),
            const SizedBox(height: 16),
            const Text("Live Requests Near You",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Card(
                child: ListTile(
                    title: const Text("Garankuwa -> Mafikeng"),
                    subtitle: Text(
                        "4 Pax - R${pricePerPerson.toStringAsFixed(0)} each - ETA $etaMinutes min - Fee R10"),
                    trailing: ElevatedButton(
                        onPressed: canAccept
                            ? () {
                                setState(() {
                                  if (acc != null) {
                                    acc['debt'] = (acc['debt'] as double) + 10;
                                    acc['trips'] = (acc['trips'] as int) + 1;
                                    acc['earned'] =
                                        (acc['earned'] as double) + totalIncome;
                                  }
                                  tripStatus = "requested";
                                  tripPickupLabel = "Garankuwa, Pretoria";
                                  tripDestLabel = "Mafikeng";
                                  tripLockedPrice = pricePerPerson;
                                  tripDriverName = fullName;
                                  tripDriverPlate = plate;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: Text(
                                        "Ride confirmed! R10 added. You now owe R${(debt + 10).toStringAsFixed(0)} - Now tap ARRIVED AT PICKUP when you get there")));
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                            backgroundColor:
                                canAccept ? Colors.green : Colors.grey),
                        child: Text(canAccept ? "ACCEPT - R10" : "BLOCKED")))),
            Card(
                child: ListTile(
                    title: const Text("Pretoria -> Rustenburg"),
                    subtitle: const Text(
                        "3 Pax - R320 each - Scheduled Tomorrow - Fee R10"),
                    trailing: ElevatedButton(
                        onPressed: canAccept
                            ? () {
                                setState(() {
                                  if (acc != null) {
                                    acc['debt'] = (acc['debt'] as double) + 10;
                                    acc['trips'] = (acc['trips'] as int) + 1;
                                  }
                                  tripStatus = "requested";
                                  tripPickupLabel = "Pretoria";
                                  tripDestLabel = "Rustenburg";
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            "Ride confirmed! R10 debt added")));
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                            backgroundColor:
                                canAccept ? Colors.green : Colors.grey),
                        child: Text(canAccept ? "ACCEPT" : "BLOCKED")))),
            const SizedBox(height: 16),
            Container(
                height: 160,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12)),
                child: FlutterMap(
                    mapController: MapController(),
                    options: MapOptions(
                        initialCenter: driverLivePos, initialZoom: 9),
                    children: [
                      TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.example.mykasisukasi'),
                      MarkerLayer(markers: [
                        Marker(
                            point: driverLivePos,
                            width: 50,
                            height: 50,
                            child: const Icon(Icons.directions_car,
                                color: Colors.green, size: 40))
                      ])
                    ])),
            const Text("Your live location - riders see this",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton(
                onPressed: () => Navigator.pushReplacement(context,
                    MaterialPageRoute(builder: (_) => const RoleSelectPage())),
                child: const Text("LOGOUT"),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.grey)),
          ]));
    }
    // === RIDER MODE - WITH LOGOUT FIX ===
    return Scaffold(
      appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 1,
          title: Row(children: [
            const Text("MyKasiSuKasi"),
            if (widget.isOwnerView)
              Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(8)),
                  child: const Text("OWNER VIEW",
                      style: TextStyle(
                          color: Colors.orange,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)))
          ]),
          actions: [
            IconButton(
                icon: const Icon(Icons.logout, color: Colors.red),
                tooltip: "Logout",
                onPressed: () => Navigator.pushReplacement(context,
                    MaterialPageRoute(builder: (_) => const RoleSelectPage())))
          ]),
      body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (widget.isOwnerView)
              Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(12)),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("You are viewing as RIDER (Owner)",
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                        GestureDetector(
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const AdminPanelPage(
                                        ownerName: "Owner", ownerCode: ""))),
                            child: const Text("OWNER PANEL >",
                                style: TextStyle(
                                    color: Colors.orange,
                                    fontWeight: FontWeight.bold)))
                      ])),
            if (widget.isOwnerView) const SizedBox(height: 12),
            tripStatusBanner(),
            Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16)),
                child: const Column(children: [
                  Icon(Icons.home, size: 80, color: Color(0xFFFF7A00)),
                  Text("MyKasiSuKasi",
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  Text("Ride Kasi, Travel Far",
                      style: TextStyle(
                          color: Color(0xFFFF7A00),
                          fontWeight: FontWeight.bold))
                ])),
            const SizedBox(height: 12),
            Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: const Color(0xFF0B4F5C),
                    borderRadius: BorderRadius.circular(16)),
                child: Column(children: [
                  Row(children: [
                    const Icon(Icons.account_balance_wallet,
                        color: Colors.white, size: 30),
                    const SizedBox(width: 12),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("WALLET BALANCE",
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 11)),
                          Text("R${walletBalance.toStringAsFixed(0)}",
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20))
                        ]),
                    const Spacer(),
                    ElevatedButton(
                        onPressed: showTopUpDialog,
                        child: const Text("TOP UP VIA CAPITEC"),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange))
                  ]),
                  const SizedBox(height: 8),
                  const Text(
                      "Pay to Capitec 1309906015 - Owner will add to wallet after checking Capitec. App does NOT access your bank. Saved even if you close app.",
                      style: TextStyle(color: Colors.white70, fontSize: 11))
                ])),
            const SizedBox(height: 16),
            const Text("Popular Kasi Routes - One Tap",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              _popularBtn("Garankuwa -> Mafikeng", "Garankuwa, Pretoria",
                  "Mafikeng", "323"),
              _popularBtn("Soshanguve -> Rustenburg", "Soshanguve",
                  "Rustenburg", "120"),
              _popularBtn("Pretoria -> Joburg", "Pretoria CBD",
                  "Johannesburg CBD", "62"),
              _popularBtn("Mabopane -> Brits", "Mabopane", "Brits", "45")
            ]),
            const SizedBox(height: 16),
            Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Your Trip",
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      GestureDetector(
                          onTap: () => pickLocation(true),
                          child: AbsorbPointer(
                              child: TextField(
                                  controller: pickupCtrl,
                                  decoration: const InputDecoration(
                                      labelText: "Pickup - Tap to Search",
                                      prefixIcon: Icon(Icons.my_location,
                                          color: Color(0xFFFF7A00)),
                                      border: OutlineInputBorder(
                                          borderRadius: BorderRadius.all(
                                              Radius.circular(12))),
                                      suffixIcon: Icon(Icons.search))))),
                      Container(
                          margin: const EdgeInsets.symmetric(vertical: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                              color: const Color(0xFFE8F5E9),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.green)),
                          child: Column(children: [
                            Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.route, color: Colors.green),
                                  const SizedBox(width: 6),
                                  Flexible(
                                      child: Text(
                                          "ROUTE: ${pickupCtrl.text} -> ${dropCtrl.text}",
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12)))
                                ]),
                            const SizedBox(height: 8),
                            Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                                  Column(children: [
                                    Text("${km.toStringAsFixed(0)} km",
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16)),
                                    const Text("Distance",
                                        style: TextStyle(fontSize: 11))
                                  ]),
                                  Column(children: [
                                    Text("${estHours.toStringAsFixed(1)} hrs",
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16)),
                                    const Text("Est. Time",
                                        style: TextStyle(fontSize: 11))
                                  ]),
                                  Column(children: [
                                    Text("R${tolls.toStringAsFixed(0)}",
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16)),
                                    const Text("Tolls",
                                        style: TextStyle(fontSize: 11))
                                  ])
                                ]),
                            Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.timer,
                                      size: 14, color: Colors.green),
                                  Text(" ETA: $etaMinutes min - Driver live",
                                      style: const TextStyle(
                                          fontSize: 11, color: Colors.green))
                                ]),
                            const Text(
                                "Route from YOUR pickup to YOUR destination",
                                style:
                                    TextStyle(fontSize: 11, color: Colors.grey))
                          ])),
                      GestureDetector(
                          onTap: () => pickLocation(false),
                          child: AbsorbPointer(
                              child: TextField(
                                  controller: dropCtrl,
                                  decoration: const InputDecoration(
                                      labelText: "Destination - Tap to Search",
                                      prefixIcon: Icon(Icons.location_on,
                                          color: Color(0xFF0B4F5C)),
                                      border: OutlineInputBorder(
                                          borderRadius: BorderRadius.all(
                                              Radius.circular(12))),
                                      suffixIcon: Icon(Icons.search))))),
                      const SizedBox(height: 10),
                      TextField(
                          controller: kmCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: "Distance KM - Auto from route",
                              prefixIcon: Icon(Icons.route),
                              border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(12))),
                              suffixText: "km"),
                          onChanged: (v) => setState(() => updateRouteInfo())),
                      const SizedBox(height: 12),
                      Row(children: [
                        Checkbox(
                            value: isReturnTrip,
                            onChanged: (v) => setState(() => isReturnTrip = v!),
                            activeColor: Colors.green),
                        const Text("Return trip - 10% discount",
                            style: TextStyle(fontSize: 13)),
                        const Spacer(),
                        Checkbox(
                            value: isScheduled,
                            onChanged: (v) => setState(() => isScheduled = v!)),
                        const Text("Schedule", style: TextStyle(fontSize: 13))
                      ]),
                      if (isScheduled)
                        Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                                color: const Color(0xFFE3F2FD),
                                borderRadius: BorderRadius.circular(8)),
                            child: const Row(children: [
                              Icon(Icons.schedule, color: Color(0xFF0B4F5C)),
                              Text(
                                  "  Tomorrow 05:00 AM - Driver will accept tonight",
                                  style: TextStyle(fontSize: 12))
                            ])),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                            child: ElevatedButton.icon(
                                onPressed: openInGoogleMaps,
                                icon: const Icon(Icons.map),
                                label: const Text("GOOGLE MAPS"),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0B4F5C),
                                    padding: const EdgeInsets.all(14)))),
                        const SizedBox(width: 10),
                        Expanded(
                            child: ElevatedButton.icon(
                                onPressed: shareWhatsApp,
                                icon: const Icon(Icons.message),
                                label: const Text("WHATSAPP"),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    padding: const EdgeInsets.all(14))))
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                            child: ElevatedButton.icon(
                                onPressed: () =>
                                    setState(() => updateRouteInfo()),
                                icon: const Icon(Icons.calculate),
                                label: const Text("CALCULATE"),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFFF7A00),
                                    padding: const EdgeInsets.all(14))))
                      ]),
                    ])),
            const SizedBox(height: 16),
            const Text("Choose Your Car - Accurate Fuel",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12)),
                child: DropdownButton<CarSpec>(
                    isExpanded: true,
                    underline: const SizedBox(),
                    value: selectedCar,
                    items: CAR_DATABASE
                        .map((c) => DropdownMenuItem(
                            value: c,
                            child: Text(c.display,
                                style: const TextStyle(fontSize: 13))))
                        .toList(),
                    onChanged: (v) => setState(() => selectedCar = v))),
            const SizedBox(height: 8),
            Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.local_gas_station, color: Colors.green),
                  const SizedBox(width: 8),
                  Text("${selectedCar!.make} ${selectedCar!.model}",
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
                  const Spacer(),
                  Text("${selectedCar!.consumption} L/100km",
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.green))
                ])),
            const SizedBox(height: 16),
            Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: const Color(0xFF0B4F5C),
                    borderRadius: BorderRadius.circular(16)),
                child: Column(children: [
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Distance",
                            style: TextStyle(color: Colors.white)),
                        Text("${km.toStringAsFixed(0)} km",
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold))
                      ]),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                            "Petrol Used - ${selectedCar!.consumption} L/100km",
                            style: const TextStyle(color: Colors.white)),
                        Text("${litres.toStringAsFixed(2)}L",
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold))
                      ]),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Tolls",
                            style: TextStyle(color: Colors.white)),
                        Text("R$tolls",
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold))
                      ]),
                  if (isReturnTrip)
                    const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Return Discount -10%",
                              style: TextStyle(color: Colors.greenAccent)),
                          Text("APPLIED",
                              style: TextStyle(
                                  color: Colors.greenAccent,
                                  fontWeight: FontWeight.bold))
                        ]),
                  const Divider(color: Colors.white38),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(priceLocked ? "PRICE LOCKED" : "Price Per Person",
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                        Text(
                            "R${(priceLocked ? lockedPrice : pricePerPerson).toStringAsFixed(0)}",
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18))
                      ]),
                  if (priceLocked)
                    const Text("Locked - won't change even if petrol rises",
                        style:
                            TextStyle(color: Colors.greenAccent, fontSize: 11))
                ])),
            const SizedBox(height: 16),
            Text("Passengers: $passengers (Split cost)",
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Slider(
                value: passengers.toDouble(),
                min: 1,
                max: 4,
                divisions: 3,
                activeColor: const Color(0xFFFF7A00),
                onChanged: (v) => setState(() => passengers = v.toInt())),
            Text(
                "Each pays: R${pricePerPerson.toStringAsFixed(0)} - Group total: R${totalIncome.toStringAsFixed(0)}",
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                    onPressed: bookRide,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF7A00),
                        padding: const EdgeInsets.all(16)),
                    child: Text(
                        priceLocked
                            ? "BOOKED - R${lockedPrice.toStringAsFixed(0)} LOCKED"
                            : "Request Verified Driver - R${pricePerPerson.toStringAsFixed(0)} (LOCK PRICE)",
                        style: const TextStyle(fontSize: 16)))),
            if (bookings.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text("Your Bookings + Trip History",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ...tripHistory.map((t) => Card(
                  child: ListTile(
                      title: Text("${t.pickup} -> ${t.dest}"),
                      subtitle: Text(
                          "${t.date} - ${t.carName} - R${t.price} ${t.isReturn ? '- Return' : ''} ${t.isScheduled ? '- Scheduled' : ''} - ${t.paymentMethod} - Driver ${t.rating}★ Car ${t.carRating}★"),
                      trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(
                              5,
                              (i) => IconButton(
                                  icon: Icon(Icons.star,
                                      size: 16,
                                      color: i < t.rating
                                          ? Colors.amber
                                          : Colors.grey),
                                  onPressed: () =>
                                      setState(() => t.rating = i + 1)))))))
            ],
          ])),
      bottomNavigationBar: BottomNavigationBar(
          currentIndex: currentIndex,
          selectedItemColor: const Color(0xFF0B4F5C),
          unselectedItemColor: Colors.grey,
          onTap: (i) => setState(() => currentIndex = i),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
            BottomNavigationBarItem(
                icon: Icon(Icons.directions_car), label: "Rides"),
            BottomNavigationBarItem(
                icon: Icon(Icons.bookmark), label: "Bookings"),
            BottomNavigationBarItem(icon: Icon(Icons.wallet), label: "Wallet"),
            BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile")
          ]),
    );
  }

  Widget _popularBtn(String label, String pickup, String dest, String kmVal) {
    return ElevatedButton(
        onPressed: () => setState(() {
              pickupCtrl.text = pickup;
              dropCtrl.text = dest;
              kmCtrl.text = kmVal;
              updateRouteInfo();
            }),
        style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF0B4F5C)),
        child: Text(label, style: const TextStyle(fontSize: 11)));
  }
}

class MapPickerPage extends StatefulWidget {
  final bool isPickup;
  const MapPickerPage({super.key, required this.isPickup});
  @override
  State<MapPickerPage> createState() => _MapPickerPageState();
}

class _MapPickerPageState extends State<MapPickerPage> {
  final MapController mapController = MapController();
  ll.LatLng center = ll.LatLng(-25.6038, 28.0880);
  ll.LatLng? picked;
  final searchCtrl = TextEditingController();
  List<Map<String, dynamic>> suggestions = [];
  bool isSearching = false;
  final List<Map<String, dynamic>> localPlaces = [
    {
      "name": "Garankuwa, Pretoria",
      "lat": -25.6038,
      "lon": 28.0880,
      "desc": "Garankuwa, Pretoria, Gauteng"
    },
    {
      "name": "Mafikeng, North West",
      "lat": -25.8653,
      "lon": 25.6447,
      "desc": "Mahikeng, North West"
    },
    {
      "name": "Mafikeng - Mmabatho",
      "lat": -25.8436,
      "lon": 25.6376,
      "desc": "Mmabatho, Mafikeng"
    },
    {
      "name": "Rustenburg",
      "lat": -25.6700,
      "lon": 27.2425,
      "desc": "Rustenburg, North West"
    },
    {
      "name": "Soshanguve",
      "lat": -25.5270,
      "lon": 28.0990,
      "desc": "Soshanguve, Pretoria"
    },
    {
      "name": "Mabopane",
      "lat": -25.4910,
      "lon": 28.0750,
      "desc": "Mabopane, Pretoria"
    },
    {
      "name": "Pretoria CBD",
      "lat": -25.7461,
      "lon": 28.1881,
      "desc": "Pretoria, Gauteng"
    },
    {
      "name": "Ottosdal",
      "lat": -26.8170,
      "lon": 25.8830,
      "desc": "Ottosdal, North West"
    },
    {
      "name": "Johannesburg CBD",
      "lat": -26.2041,
      "lon": 28.0473,
      "desc": "Johannesburg, Gauteng"
    },
    {
      "name": "Soweto",
      "lat": -26.2600,
      "lon": 27.8700,
      "desc": "Soweto, Johannesburg"
    },
    {
      "name": "Mamelodi",
      "lat": -25.7170,
      "lon": 28.3980,
      "desc": "Mamelodi, Pretoria"
    },
    {
      "name": "Brits",
      "lat": -25.6350,
      "lon": 27.7820,
      "desc": "Brits, North West"
    },
  ];
  @override
  void initState() {
    super.initState();
    picked = center;
    suggestions = localPlaces;
  }

  void searchPlaces(String query) async {
    String q = query.toLowerCase().trim();
    if (q.isEmpty) {
      setState(() => suggestions = localPlaces);
      return;
    }
    List<Map<String, dynamic>> local = localPlaces
        .where((p) => p['name'].toString().toLowerCase().contains(q))
        .toList();
    setState(() => suggestions = local);
    if (local.isEmpty && q.length >= 3) {
      setState(() => isSearching = true);
      try {
        final url = Uri.parse(
            'https://photon.komoot.io/api/?q=${Uri.encodeComponent(query)}&limit=5');
        final res = await http.get(url);
        if (res.statusCode == 200) {
          var data = json.decode(res.body);
          List<Map<String, dynamic>> online = [];
          for (var f in data['features']) {
            var coords = f['geometry']['coordinates'];
            var props = f['properties'];
            online.add({
              "name": props['name'] ?? query,
              "lat": coords[1],
              "lon": coords[0],
              "desc": "${props['name'] ?? ''}, ${props['city'] ?? ''}"
            });
          }
          setState(() {
            suggestions = online;
            isSearching = false;
          });
        } else {
          setState(() => isSearching = false);
        }
      } catch (e) {
        setState(() => isSearching = false);
      }
    }
  }

  void selectPlace(Map<String, dynamic> place) {
    ll.LatLng newPos = ll.LatLng(place['lat'], place['lon']);
    mapController.move(newPos, 14);
    setState(() {
      picked = newPos;
      searchCtrl.text = place['name'];
      suggestions = [];
    });
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Found: ${place['name']} - Map zoomed!")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
            title:
                Text(widget.isPickup ? "Search Pickup" : "Search Destination"),
            backgroundColor: const Color(0xFF0B4F5C)),
        body: Stack(children: [
          FlutterMap(
              mapController: mapController,
              options: MapOptions(
                  initialCenter: center,
                  initialZoom: 11,
                  onTap: (_, pos) async {
                    setState(() => picked = pos);
                    try {
                      List<Placemark> places = await placemarkFromCoordinates(
                          pos.latitude, pos.longitude);
                      if (places.isNotEmpty)
                        searchCtrl.text = places[0].locality ?? "Pinned";
                    } catch (_) {}
                  }),
              children: [
                TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.mykasisukasi'),
                if (picked != null)
                  MarkerLayer(markers: [
                    Marker(
                        point: picked!,
                        width: 60,
                        height: 60,
                        child: const Icon(Icons.location_on,
                            size: 50, color: Colors.red))
                  ])
              ]),
          Column(children: [
            Container(
                color: Colors.white,
                padding: const EdgeInsets.all(8),
                child: TextField(
                    controller: searchCtrl,
                    decoration: InputDecoration(
                        hintText: widget.isPickup
                            ? "Type pickup e.g. Garankuwa"
                            : "Type destination e.g. Mafikeng",
                        prefixIcon: const Icon(Icons.search),
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white),
                    onChanged: searchPlaces,
                    onTap: () {
                      if (suggestions.isEmpty)
                        setState(() => suggestions = localPlaces);
                    })),
            if (suggestions.isNotEmpty)
              Container(
                  constraints: const BoxConstraints(maxHeight: 300),
                  color: Colors.white,
                  child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: suggestions.length,
                      itemBuilder: (ctx, i) {
                        final p = suggestions[i];
                        return ListTile(
                            leading: const Icon(Icons.location_on,
                                color: Color(0xFFFF7A00)),
                            title: Text(p['name'],
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 14)),
                            subtitle: Text(p['desc'],
                                style: const TextStyle(fontSize: 12)),
                            onTap: () => selectPlace(p));
                      })),
          ]),
        ]),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: () => Navigator.pop(context, {
                  'pos': picked,
                  'name': searchCtrl.text.isEmpty
                      ? "Pinned Location"
                      : searchCtrl.text
                }),
            label:
                Text("CONFIRM - ${widget.isPickup ? 'PICKUP' : 'DESTINATION'}"),
            icon: const Icon(Icons.pin_drop),
            backgroundColor: const Color(0xFFFF7A00)));
  }
}
