import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class BuyerMapView extends StatefulWidget {
  const BuyerMapView({super.key});

  @override
  State<BuyerMapView> createState() => _BuyerMapViewState();
}

class _BuyerMapViewState extends State<BuyerMapView> {
  late GoogleMapController mapController;
  
  // Center of Laurel, Batangas
  final LatLng _laurelCenter = const LatLng(14.0445, 120.9320);

  // Using Circles instead of Markers to protect farmer privacy
  final Set<Circle> _farmZones = {};

  @override
  void initState() {
    super.initState();
    _loadPrivacySafeZones();
  }

  void _loadPrivacySafeZones() {
    setState(() {
      _farmZones.addAll([
        Circle(
          circleId: const CircleId('zone_1'),
          // Offset coordinates slightly from the actual farm
          center: const LatLng(14.0500, 120.9350), 
          radius: 600, // 600-meter approximate radius
          fillColor: Colors.green.withOpacity(0.2),
          strokeColor: Colors.green[800]!,
          strokeWidth: 2,
          consumeTapEvents: true, // Allows the circle to be tapped
          onTap: () => _showFarmDetails(
            farmName: 'San Juan Estates (Vicinity)', 
            distance: '~2.4 km away', 
            topProducts: 'Brahmam Cattle, Robusta Beans',
          ),
        ),
        Circle(
          circleId: const CircleId('zone_2'),
          center: const LatLng(14.0350, 120.9200),
          radius: 800, // 800-meter approximate radius
          fillColor: Colors.green.withOpacity(0.2),
          strokeColor: Colors.green[800]!,
          strokeWidth: 2,
          consumeTapEvents: true,
          onTap: () => _showFarmDetails(
            farmName: 'Mang Jose Harvest (Vicinity)', 
            distance: '~4.1 km away', 
            topProducts: 'Heirloom Tomatoes, Corn',
          ),
        ),
      ]);
    });
  }

  void _showFarmDetails({required String farmName, required String distance, required String topProducts}) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      farmName,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.all(8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'VERIFIED',
                      style: TextStyle(color: Colors.green[800], fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.location_on_outlined, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text('Laurel, Batangas • $distance', style: TextStyle(color: Colors.grey[600])),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.privacy_tip_outlined, size: 16, color: Colors.orange[800]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Exact address is hidden for farmer privacy and will be revealed upon order confirmation.',
                        style: TextStyle(fontSize: 12, color: Colors.orange[900]),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('Top Products in this Zone', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(topProducts, style: TextStyle(color: Colors.grey[800])),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    // Navigate to Farm Profile
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[800],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('View Farm Profile'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (controller) => mapController = controller,
            initialCameraPosition: CameraPosition(target: _laurelCenter, zoom: 13.5),
            circles: _farmZones, // Using circles instead of markers
            myLocationEnabled: true,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false, // Disables external routing to Google Maps app prematurely
          ),
          Positioned(
            top: 50,
            left: 16,
            right: 16,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4)),
                ],
              ),
              child: const TextField(
                decoration: InputDecoration(
                  hintText: 'Search nearby zones...',
                  prefixIcon: Icon(Icons.search, color: Colors.grey),
                  suffixIcon: Icon(Icons.tune, color: Colors.grey),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}