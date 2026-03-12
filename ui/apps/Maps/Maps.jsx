import React, { useState, useEffect, useRef } from 'react';
import { MapContainer, TileLayer, Marker, Popup, useMap } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';

// Fix for default markers
delete L.Icon.Default.prototype._getIconUrl;
L.Icon.Default.mergeOptions({
  iconRetinaUrl: require('leaflet/dist/images/marker-icon-2x.png'),
  iconUrl: require('leaflet/dist/images/marker-icon.png'),
  shadowUrl: require('leaflet/dist/images/marker-shadow.png'),
});

const Maps = () => {
  const [currentLocation, setCurrentLocation] = useState([0, 0]);
  const [savedLocations, setSavedLocations] = useState([]);
  const [isTracking, setIsTracking] = useState(false);
  const [grabDrivers, setGrabDrivers] = useState([]);
  const [isGrabDriver, setIsGrabDriver] = useState(false);
  const [showGrabDrivers, setShowGrabDrivers] = useState(false);
  const mapRef = useRef();

  // Component để cập nhật vị trí map
  const LocationUpdater = ({ position }) => {
    const map = useMap();
    
    useEffect(() => {
      if (position[0] !== 0 && position[1] !== 0) {
        map.setView(position, map.getZoom());
      }
    }, [position, map]);
    
    return null;
  };

  // Lấy vị trí hiện tại
  useEffect(() => {
    window.postMessage({
      type: 'Maps',
      action: 'getCurrentLocation'
    }, '*');
  }, []);

  // Lấy danh sách locations đã lưu
  useEffect(() => {
    window.postMessage({
      type: 'Maps',
      action: 'getLocations'
    }, '*');
  }, []);

  // Lắng nghe events từ client
  useEffect(() => {
    const handleMessage = (event) => {
      if (event.data.type === 'maps:updateCoords') {
        setCurrentLocation([event.data.y, event.data.x]);
      } else if (event.data.type === 'grab:updateDriverStatus') {
        setIsGrabDriver(event.data.isDriver);
      }
    };

    window.addEventListener('message', handleMessage);
    return () => window.removeEventListener('message', handleMessage);
  }, []);

  // Bật/tắt theo dõi vị trí
  const toggleTracking = () => {
    const newTracking = !isTracking;
    setIsTracking(newTracking);
    
    window.postMessage({
      type: 'Maps',
      action: 'toggleUpdateCoords',
      toggle: newTracking
    }, '*');
  };

  // Đặt waypoint
  const setWaypoint = (lat, lng) => {
    window.postMessage({
      type: 'Maps',
      action: 'setWaypoint',
      data: { x: lng, y: lat }
    }, '*');
  };

  // Thêm location mới
  const addLocation = (name, lat, lng) => {
    window.postMessage({
      type: 'Maps',
      action: 'addLocation',
      name: name,
      location: [lng, lat]
    }, '*');
  };

  // Toggle Grab driver
  const toggleGrabDriver = () => {
    window.postMessage({
      type: 'Maps',
      action: 'toggleGrabDriver'
    }, '*');
  };

  // Hiển thị/ẩn Grab drivers
  const toggleShowGrabDrivers = () => {
    const newShow = !showGrabDrivers;
    setShowGrabDrivers(newShow);
    
    if (newShow) {
      window.postMessage({
        type: 'Maps',
        action: 'getAllGrabDrivers'
      }, '*');
    } else {
      window.postMessage({
        type: 'Maps',
        action: 'hideTaxiBlips'
      }, '*');
    }
  };

  // Request Grab ride
  const requestGrabRide = () => {
    window.postMessage({
      type: 'Maps',
      action: 'requestGrabRide'
    }, '*');
  };

  return (
    <div className="maps-container" style={{ height: '100vh', width: '100%' }}>
      {/* Controls */}
      <div className="maps-controls" style={{
        position: 'absolute',
        top: '10px',
        left: '10px',
        zIndex: 1000,
        background: 'rgba(0,0,0,0.8)',
        padding: '10px',
        borderRadius: '8px',
        color: 'white'
      }}>
        <button 
          onClick={toggleTracking}
          style={{
            background: isTracking ? '#4CAF50' : '#f44336',
            color: 'white',
            border: 'none',
            padding: '8px 16px',
            borderRadius: '4px',
            marginRight: '8px',
            cursor: 'pointer'
          }}
        >
          {isTracking ? 'Tắt theo dõi' : 'Bật theo dõi'}
        </button>
        
        <button 
          onClick={toggleGrabDriver}
          style={{
            background: isGrabDriver ? '#FF9800' : '#2196F3',
            color: 'white',
            border: 'none',
            padding: '8px 16px',
            borderRadius: '4px',
            marginRight: '8px',
            cursor: 'pointer'
          }}
        >
          {isGrabDriver ? 'Tắt Grab' : 'Bật Grab'}
        </button>
        
        <button 
          onClick={toggleShowGrabDrivers}
          style={{
            background: showGrabDrivers ? '#9C27B0' : '#607D8B',
            color: 'white',
            border: 'none',
            padding: '8px 16px',
            borderRadius: '4px',
            marginRight: '8px',
            cursor: 'pointer'
          }}
        >
          {showGrabDrivers ? 'Ẩn tài xế' : 'Hiện tài xế'}
        </button>
        
        <button 
          onClick={requestGrabRide}
          style={{
            background: '#4CAF50',
            color: 'white',
            border: 'none',
            padding: '8px 16px',
            borderRadius: '4px',
            cursor: 'pointer'
          }}
        >
          Gọi Grab
        </button>
      </div>

      {/* Map */}
      <MapContainer
        center={currentLocation}
        zoom={13}
        style={{ height: '100%', width: '100%' }}
        ref={mapRef}
      >
        <TileLayer
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
        />
        
        <LocationUpdater position={currentLocation} />
        
        {/* Current location marker */}
        {currentLocation[0] !== 0 && currentLocation[1] !== 0 && (
          <Marker position={currentLocation}>
            <Popup>Vị trí hiện tại của bạn</Popup>
          </Marker>
        )}
        
        {/* Saved locations */}
        {savedLocations.map((location) => (
          <Marker 
            key={location.id} 
            position={location.position}
            eventHandlers={{
              click: () => {
                setWaypoint(location.position[0], location.position[1]);
              }
            }}
          >
            <Popup>{location.name}</Popup>
          </Marker>
        ))}
        
        {/* Grab drivers */}
        {showGrabDrivers && grabDrivers.map((driver, index) => (
          <Marker 
            key={index}
            position={[driver.y, driver.x]}
            icon={L.icon({
              iconUrl: 'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-yellow.png',
              shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/0.7.7/images/marker-shadow.png',
              iconSize: [25, 41],
              iconAnchor: [12, 41],
              popupAnchor: [1, -34],
              shadowSize: [41, 41]
            })}
          >
            <Popup>
              Tài xế Grab
              <br />
              Khoảng cách: {driver.distance}m
              <br />
              Trạng thái: {driver.busy ? 'Bận' : 'Rảnh'}
            </Popup>
          </Marker>
        ))}
      </MapContainer>
    </div>
  );
};

export default Maps;