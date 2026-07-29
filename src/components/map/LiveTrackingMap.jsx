import { useEffect, useState } from "react";
import { MapContainer, TileLayer, Marker, Popup, Polyline, useMap } from "react-leaflet";
import L from "leaflet";

// Reliable inline SVG data URIs for map markers
const driverIconUrl = "data:image/svg+xml;charset=UTF-8," + encodeURIComponent(`
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="48px" height="48px">
  <path fill="#e74c3c" d="M62 26H50V14c0-2.2-1.8-4-4-4H18c-2.2 0-4 1.8-4 4v12H2c-1.1 0-2 .9-2 2v18h8.5c.8 4.5 4.8 8 9.5 8s8.7-3.5 9.5-8H37c.8 4.5 4.8 8 9.5 8s8.7-3.5 9.5-8H64V36l-2-10z"/>
  <path fill="#fff" d="M22 18h20v14H22z"/>
  <path fill="#e74c3c" d="M30 20h4v10h-4z"/>
  <path fill="#e74c3c" d="M26 23h12v4H26z"/>
  <circle fill="#2c3e50" cx="18" cy="46" r="6"/>
  <circle fill="#bdc3c7" cx="18" cy="46" r="3"/>
  <circle fill="#2c3e50" cx="46" cy="46" r="6"/>
  <circle fill="#bdc3c7" cx="46" cy="46" r="3"/>
  <path fill="#f1c40f" d="M54 30h8v4h-8zM2 30h6v4H2z"/>
</svg>
`);

const userIconUrl = "data:image/svg+xml;charset=UTF-8," + encodeURIComponent(`
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="48px" height="48px">
  <path fill="#3498db" d="M32 0C18.7 0 8 10.7 8 24c0 18 24 40 24 40s24-22 24-40C56 10.7 45.3 0 32 0z"/>
  <circle fill="#fff" cx="32" cy="24" r="12"/>
  <circle fill="#3498db" cx="32" cy="21" r="5"/>
  <path fill="#3498db" d="M38.5 31c-1.5-2-3.7-3.2-6.5-3.2s-5 1.2-6.5 3.2c-.8 1-1.3 2.3-1.5 3.8H40c-.2-1.5-.7-2.8-1.5-3.8z"/>
</svg>
`);

const driverIcon = new L.Icon({
  iconUrl: driverIconUrl,
  iconSize: [48, 48],
  iconAnchor: [24, 24],
  popupAnchor: [0, -24],
  className: "leaflet-driver-marker"
});

const userIcon = new L.Icon({
  iconUrl: userIconUrl,
  iconSize: [48, 48],
  iconAnchor: [24, 48], // Pointing tip to exactly the spot
  popupAnchor: [0, -48]
});

const hospitalIconUrl = "data:image/svg+xml;charset=UTF-8," + encodeURIComponent(`
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="48px" height="48px">
  <path fill="#2ecc71" d="M32 0C18.7 0 8 10.7 8 24c0 18 24 40 24 40s24-22 24-40C56 10.7 45.3 0 32 0z"/>
  <rect fill="#fff" x="28" y="12" width="8" height="24"/>
  <rect fill="#fff" x="20" y="20" width="24" height="8"/>
</svg>
`);

const hospitalIcon = new L.Icon({
  iconUrl: hospitalIconUrl,
  iconSize: [48, 48],
  iconAnchor: [24, 48],
  popupAnchor: [0, -48]
});

// Helper component to auto-fit map bounds tightly over patient, driver and hospital
function MapBoundsFit({ userLocation, driverLocation, hospitalLocation }) {
  const map = useMap();
  useEffect(() => {
    const points = [];
    if (userLocation?.lat && userLocation?.lng) points.push([userLocation.lat, userLocation.lng]);
    if (driverLocation?.lat && driverLocation?.lng) points.push([driverLocation.lat, driverLocation.lng]);
    if (hospitalLocation?.lat && hospitalLocation?.lng) points.push([hospitalLocation.lat, hospitalLocation.lng]);

    if (points.length >= 2) {
      const bounds = L.latLngBounds(points);
      map.fitBounds(bounds, { padding: [50, 50] });
    } else if (points.length === 1) {
      map.setView(points[0], 15);
    }
  }, [map, userLocation, driverLocation, hospitalLocation]);
  return null;
}

const calculateETA = (loc1, loc2) => {
  if (!loc1?.lat || !loc1?.lng || !loc2?.lat || !loc2?.lng) {
    return { distance: null, duration: null, text: "Calculating..." };
  }
  const R = 6371; // Earth radius in km
  const dLat = ((loc2.lat - loc1.lat) * Math.PI) / 180;
  const dLon = ((loc2.lng - loc1.lng) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((loc1.lat * Math.PI) / 180) *
      Math.cos((loc2.lat * Math.PI) / 180) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  const distanceKm = R * c;
  
  // Average traffic speed: 30 km/h
  const durationMin = Math.round((distanceKm / 30) * 60);
  return {
    distance: distanceKm.toFixed(1),
    duration: durationMin,
    text: durationMin <= 1 ? "Arriving" : `${durationMin} mins`
  };
};

export default function LiveTrackingMap({
  userLocation,
  hospitalLocation,
  driverLocation,
  hospitalName,
  hospitalAddress,
  height = "400px"
}) {
  const [routeCoords, setRouteCoords] = useState(null);
  const destination =
    hospitalLocation?.lat
      ? hospitalLocation
      : userLocation;
  useEffect(() => {
    let active = true;
    
    const fetchRoute = async () => {
      // We only execute routing if both vectors are valid
      const targetDest = hospitalLocation?.lat ? hospitalLocation : userLocation;
      if (targetDest?.lat && driverLocation?.lat) {
        try {
           // Overly important mapping difference: ORS strictly takes [lng, lat] syntax!
           const start = `${driverLocation.lng},${driverLocation.lat}`;
           const end = `${targetDest.lng},${targetDest.lat}`;
           const apiKey = import.meta.env.VITE_ORS_API_KEY;

           if (!apiKey) {
               console.warn("Missing VITE_ORS_API_KEY. Navigation routing line will not render natively");
               return;
           }

           const res = await fetch(`https://api.openrouteservice.org/v2/directions/driving-car?api_key=${apiKey}&start=${start}&end=${end}`);
           if (!res.ok) throw new Error("ORS Routing Calculation Failure");
           const data = await res.json();
           
           if (data.features && data.features.length > 0 && active) {
              const geometry = data.features[0].geometry.coordinates;
              // React-Leaflet Polyline strictly accepts [lat, lng] array maps, so we reverse it!
              const leafletCoords = geometry.map(coord => [coord[1], coord[0]]);
              setRouteCoords(leafletCoords);
           }
        } catch (error) {
           console.error("Failed to fetch Live ORS Map routing:", error);
        }
      } else {
        setRouteCoords(null);
      }
    };

    fetchRoute();
    
    // Prevent fetching race condition
    return () => { active = false; };
  }, [userLocation, driverLocation, hospitalLocation]);

  const center = destination?.lat ? [destination.lat, destination.lng] 
               : driverLocation?.lat ? [driverLocation.lat, driverLocation.lng] 
               : hospitalLocation?.lat ? [hospitalLocation.lat, hospitalLocation.lng]
               : [20.5937, 78.9629]; // Default Geographic India point map

  const targetDest = hospitalLocation?.lat ? hospitalLocation : userLocation;
  const etaInfo = (driverLocation?.lat && targetDest?.lat)
    ? calculateETA(driverLocation, targetDest)
    : null;

  return (
    <div 
      className="w-full rounded-2xl overflow-hidden shadow-lg border border-gray-200 dark:border-gray-700 relative z-0 flex flex-col" 
      style={{ height: height, minHeight: height }}
    >
      
      {/* Visual Overlay Error Warning */}
      {!import.meta.env.VITE_ORS_API_KEY && (
         <div className="absolute top-2 left-2 z-[1000] bg-yellow-100 border border-yellow-400 text-yellow-700 px-3 py-1 rounded text-xs opacity-90 shadow">
            Missing OpenRouteService API Key (Line disabled)
         </div>
      )}

      {/* Floating ETA & Distance card */}
      {etaInfo && etaInfo.distance && (
         <div className="absolute bottom-4 left-4 z-[1000] bg-white/90 dark:bg-slate-900/90 backdrop-blur-md border border-slate-200 dark:border-slate-800 p-4 rounded-2xl shadow-xl flex items-center gap-4 transition-all">
            <div className="w-10 h-10 bg-red-105 dark:bg-red-950/40 rounded-xl flex items-center justify-center text-xl shrink-0">
               🚑
            </div>
            <div>
               <p className="text-[10px] text-gray-500 dark:text-gray-400 uppercase font-black tracking-wider">Estimated Arrival</p>
               <p className="text-sm font-black text-slate-800 dark:text-white mt-0.5">{etaInfo.text} ({etaInfo.distance} km remaining)</p>
            </div>
         </div>
      )}

      {/* Primary Leaflet Container Engine Node */}
      <MapContainer 
         center={center} 
         zoom={13} 
         style={{ width: "100%", height: "100%", minHeight: "100%" }} 
         scrollWheelZoom={false}
      >
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
        />

        {/* Bind Custom Auto Map Resizer Engine Module Component Hook */}
        <MapBoundsFit userLocation={userLocation} driverLocation={driverLocation} hospitalLocation={hospitalLocation} />

        {/* User Patient Marker View */}
        {userLocation?.lat && (
          <Marker
            position={[userLocation.lat, userLocation.lng]}
            icon={userIcon}
          >
            <Popup>
              Patient Location
            </Popup>
          </Marker>
        )}

        {/* Emergency Driver Marker View */}
        {driverLocation?.lat && (
          <Marker position={[driverLocation.lat, driverLocation.lng]} icon={driverIcon}>
             <Popup>Ambulance Driver Live</Popup>
          </Marker>
        )}

        {/* Hospital Destination Marker View */}
        {hospitalLocation?.lat && (
          <Marker position={[hospitalLocation.lat, hospitalLocation.lng]} icon={hospitalIcon}>
             <Popup>
               <div className="text-xs">
                 <p className="font-bold">{hospitalName || "Hospital Destination"}</p>
                 <p className="text-gray-500">{hospitalAddress || ""}</p>
               </div>
             </Popup>
          </Marker>
        )}

        {/* Dynamic ORS Red Polyline Route Draw Render View */}
        {routeCoords && (
          <Polyline positions={routeCoords} color="#EF4444" weight={5} opacity={0.8} dashArray="10, 10" />
        )}
      </MapContainer>
    </div>
  );
}
