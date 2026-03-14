// Global state
let isGrabDriver = false;
let hasActiveRide = false;
let currentLocation = { x: 0, y: 0 };
let pickupLocation = null;
let dropoffLocation = null;
let isLoading = false;
let map = null;
let currentMarker = null;
let driverMarker = null;
let pickupMarker = null;
let dropoffMarker = null;
let driverMarkers = [];
let isFollowingPlayer = true;
let isTrackingCoords = false;
let currentView = 'main'; // main, booking, driver, activeRide
let pendingRideRequest = null;
let currentRideData = null;
let rideStatus = null; // waiting, picking_up, in_progress, completed, cancelled

// Map initialization - Using EXACT same logic as Maps-6f0d30bc.js
function initMap() {
    try {
        // Exact config from Maps-6f0d30bc.js
        const mapConfig = {
            image: [16384, 24576],
            topLeft: [-4140, 8400],
            bottomRight: [4860, -5100],
            tileServer: "https://assets.loaf-scripts.com/map-tiles/gtav/main/{layer}/{z}/{x}/{y}.jpg",
            defaultCenter: [1650, 450],
            defaultZoom: 3
        };

        // Create custom CRS exactly like Maps-6f0d30bc.js
        const createCustomCRS = function (config) {
            const image = config.image;
            const topLeft = config.topLeft;
            const bottomRight = config.bottomRight;
            const tileSize = 256;

            // Calculate max zoom
            const maxZoom = Math.ceil(Math.log(Math.max(image[0], image[1]) / tileSize) / Math.log(2));

            // Calculate dimensions
            const gameWidth = bottomRight[0] - topLeft[0];
            const gameHeight = bottomRight[1] - topLeft[1];

            if (gameWidth === 0 || gameHeight === 0) {
                return L.CRS.Simple;
            }

            // Calculate transformation parameters (exact same as Maps-6f0d30bc.js)
            const scale = Math.pow(2, maxZoom);
            const imageWidth = image[0];
            const imageHeight = image[1];
            const scaleX = imageWidth / (gameWidth * scale);
            const scaleY = imageHeight / (gameHeight * scale);
            const offsetX = -scaleX * topLeft[0];
            const offsetY = -scaleY * topLeft[1];

            // Create custom CRS
            return L.extend({}, L.CRS.Simple, {
                projection: L.Projection.LonLat,
                transformation: new L.Transformation(scaleX, offsetX, scaleY, offsetY),
                scale: function (zoom) {
                    return Math.pow(2, zoom);
                },
                zoom: function (scale) {
                    return Math.log(scale) / Math.LN2;
                }
            });
        };

        const customCRS = createCustomCRS(mapConfig);

        // Create map with custom CRS
        map = L.map('map', {
            crs: customCRS,
            center: mapConfig.defaultCenter,
            zoom: mapConfig.defaultZoom,
            zoomControl: true,
            attributionControl: false,
            maxBounds: [mapConfig.topLeft, mapConfig.bottomRight],
            maxBoundsViscosity: 1.0
        });

        // Create tile layers
        const renderUrl = mapConfig.tileServer.replace('{layer}', 'render');
        const gameUrl = mapConfig.tileServer.replace('{layer}', 'game');
        const printUrl = mapConfig.tileServer.replace('{layer}', 'print');

        const renderLayer = L.tileLayer(renderUrl, {
            attribution: '',
            maxZoom: 6,
            minZoom: 1,
            tileSize: 256,
            zoomOffset: 0,
            noWrap: true,
            bounds: [mapConfig.topLeft, mapConfig.bottomRight]
        });

        const gameLayer = L.tileLayer(gameUrl, {
            attribution: '',
            maxZoom: 6,
            minZoom: 1,
            tileSize: 256,
            zoomOffset: 0,
            noWrap: true,
            bounds: [mapConfig.topLeft, mapConfig.bottomRight]
        });

        const printLayer = L.tileLayer(printUrl, {
            attribution: '',
            maxZoom: 6,
            minZoom: 1,
            tileSize: 256,
            zoomOffset: 0,
            noWrap: true,
            bounds: [mapConfig.topLeft, mapConfig.bottomRight]
        });

        // Add error handling
        renderLayer.on('tileerror', function (error) {
            // Silent error handling
        });
        gameLayer.on('tileerror', function (error) {
            // Silent error handling
        });
        printLayer.on('tileerror', function (error) {
            // Silent error handling
        });

        // Add default tile layer to map
        renderLayer.addTo(map);

        // Add layer control
        const baseMaps = {
            "Bản đồ màu (Render)": renderLayer,
            "Bản đồ gốc (Game)": gameLayer,
            "Bản đồ vệ tinh (Print)": printLayer
        };
        L.control.layers(baseMaps).addTo(map);

        // Tắt follow mode khi user kéo map thủ công
        map.on('dragstart', function() {
            isFollowingPlayer = false;
        });

        // Set view
        map.setView(mapConfig.defaultCenter, mapConfig.defaultZoom);

        // Ensure map container is properly sized
        setTimeout(() => {
            map.invalidateSize();
        }, 100);

        // Set initial location if available
        if (currentLocation.x !== 0 && currentLocation.y !== 0) {
            updateMapLocation(currentLocation.x, currentLocation.y);
        }

        return true;
    } catch (error) {
        return false;
    }
}

// Update map location - Using game coordinates directly
function updateMapLocation(x, y, followPlayer = true) {
    if (!map) {
        return;
    }

    try {
        // Use [y, x] for Leaflet coordinates (Lat = Y, Lng = X)
        const gameCoords = [Math.round(y), Math.round(x)];

        // Tự động follow player khi di chuyển
        if (followPlayer) {
            const currentZoom = map.getZoom();
            map.setView(gameCoords, currentZoom);
        }

        // Force remove old marker với animation
        if (currentMarker) {
            map.removeLayer(currentMarker);
            currentMarker = null;
        }

        // Create marker icon based on driver status - FIX: Sử dụng màu xanh lá cho tài xế
        let iconColor = isGrabDriver ? 'green' : 'blue';
        let iconUrl = `https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-${iconColor}.png?t=${Date.now()}`;

        const customIcon = L.icon({
            iconUrl: iconUrl,
            shadowUrl: `https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-shadow.png?t=${Date.now()}`,
            iconSize: [25, 41],
            iconAnchor: [12, 41],
            popupAnchor: [1, -34],
            shadowSize: [41, 41]
        });

        // Force create new marker với unique ID
        const popupText = isGrabDriver ? 'Vị trí tài xế (Bạn)' : 'Vị trí của bạn';
        currentMarker = L.marker(gameCoords, { 
            icon: customIcon,
            riseOnHover: true,
            title: popupText
        })
            .addTo(map)
            .bindPopup(popupText);

        // Click vào marker để bật lại follow mode
        currentMarker.on('click', function() {
            isFollowingPlayer = true;
        });

        // Force refresh map tiles
        setTimeout(() => {
            map.invalidateSize();
        }, 50);

    } catch (error) {
        // Silent error handling
    }
}

// Clear all driver markers
function clearDriverMarkers() {
    driverMarkers.forEach(marker => {
        if (map.hasLayer(marker)) {
            map.removeLayer(marker);
        }
    });
    driverMarkers = [];
}

// Update driver marker (for tracking driver during ride)
function updateDriverMarker(x, y, vehiclePlate) {
    if (!map) return;
    
    try {
        const gameCoords = [Math.round(y), Math.round(x)];
        
        if (driverMarker && map.hasLayer(driverMarker)) {
            // Update existing marker position
            driverMarker.setLatLng(gameCoords);
        } else {
            // Create new driver marker
            const driverIcon = L.icon({
                iconUrl: 'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-blue.png',
                shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-shadow.png',
                iconSize: [25, 41],
                iconAnchor: [12, 41],
                popupAnchor: [1, -34],
                shadowSize: [41, 41]
            });
            
            driverMarker = L.marker(gameCoords, { icon: driverIcon })
                .addTo(map)
                .bindPopup(`🚗 Tài xế<br/>Biển số: ${vehiclePlate || 'N/A'}`);
        }
    } catch (error) {
        // Silent error handling
    }
}
// Create pickup marker
function createPickupMarker(x, y) {
    if (!map) return;
    
    try {
        const gameCoords = [Math.round(y), Math.round(x)];
        
        if (pickupMarker && map.hasLayer(pickupMarker)) {
            map.removeLayer(pickupMarker);
        }
        
        const pickupIcon = L.icon({
            iconUrl: 'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-green.png',
            shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-shadow.png',
            iconSize: [25, 41],
            iconAnchor: [12, 41],
            popupAnchor: [1, -34],
            shadowSize: [41, 41]
        });
        
        pickupMarker = L.marker(gameCoords, { icon: pickupIcon })
            .addTo(map)
            .bindPopup('📍 Điểm đón');
    } catch (error) {
        // Silent error handling
    }
}

// Create dropoff marker
function createDropoffMarker(x, y) {
    if (!map) return;
    
    try {
        const gameCoords = [Math.round(y), Math.round(x)];
        
        if (dropoffMarker && map.hasLayer(dropoffMarker)) {
            map.removeLayer(dropoffMarker);
        }
        
        const dropoffIcon = L.icon({
            iconUrl: 'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-orange.png',
            shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-shadow.png',
            iconSize: [25, 41],
            iconAnchor: [12, 41],
            popupAnchor: [1, -34],
            shadowSize: [41, 41]
        });
        
        dropoffMarker = L.marker(gameCoords, { icon: dropoffIcon })
            .addTo(map)
            .bindPopup('🏁 Điểm trả');
    } catch (error) {
        // Silent error handling
    }
}

// Cleanup all ride-related markers
function cleanupRideMarkers() {
    if (driverMarker && map.hasLayer(driverMarker)) {
        map.removeLayer(driverMarker);
        driverMarker = null;
    }
    if (pickupMarker && map.hasLayer(pickupMarker)) {
        map.removeLayer(pickupMarker);
        pickupMarker = null;
    }
    if (dropoffMarker && map.hasLayer(dropoffMarker)) {
        map.removeLayer(dropoffMarker);
        dropoffMarker = null;
    }
    pickupLocation = null;
    dropoffLocation = null;
    
    // Ẩn thông tin địa chỉ
    pickupInfo.classList.add('hidden');
    dropoffInfo.classList.add('hidden');
}

// Add driver markers - Using game coordinates directly
function addDriverMarkers(drivers) {
    try {
        clearDriverMarkers();

        if (!drivers || !Array.isArray(drivers)) {
            return;
        }

        drivers.forEach((driver, index) => {
            if (!driver.coords && !(driver.x && driver.y)) {
                return;
            }

            // Handle both coordinate formats
            let x, y;
            if (driver.coords) {
                x = driver.coords.x;
                y = driver.coords.y;
            } else {
                x = driver.x;
                y = driver.y;
            }

            // Use [y, x] for Leaflet coordinates (Lat = Y, Lng = X)
            const gameCoords = [Math.round(y), Math.round(x)];

            const iconColor = driver.busy ? 'red' : 'green';
            const iconUrl = `https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-${iconColor}.png`;

            const driverIcon = L.icon({
                iconUrl: iconUrl,
                shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-shadow.png',
                iconSize: [20, 33],
                iconAnchor: [10, 33],
                popupAnchor: [1, -28],
                shadowSize: [33, 33]
            });

            const marker = L.marker(gameCoords, { icon: driverIcon })
                .addTo(map)
                .bindPopup(`
                    <div>
                        <strong>🚗 Tài xế Grab</strong><br/>
                        Khoảng cách: ${driver.distance || 0}m<br/>
                        Trạng thái: ${driver.busy ? '🔴 Bận' : '🟢 Rảnh'}<br/>
                        Tọa độ: ${Math.round(x)}, ${Math.round(y)}
                    </div>
                `);

            driverMarkers.push(marker);
        });

        // Update driver count
        driverCount.classList.remove('hidden');
        onlineDrivers.textContent = drivers.length;

    } catch (error) {
        // Silent error handling
    }
}

// DOM elements
const statusBadge = document.getElementById('statusBadge');
const statusBar = document.getElementById('statusBar');
const statusText = document.getElementById('statusText');
const currentStatus = document.getElementById('currentStatus');
const currentLocationEl = document.getElementById('currentLocation');
const pickupLocationEl = document.getElementById('pickupLocation');
const dropoffLocationEl = document.getElementById('dropoffLocation');
const pickupInfo = document.getElementById('pickupInfo');
const dropoffInfo = document.getElementById('dropoffInfo');
const priceInfo = document.getElementById('priceInfo');
const estimatedPrice = document.getElementById('estimatedPrice');
const rideInfo = document.getElementById('rideInfo');
const rideDetails = document.getElementById('rideDetails');
const driverCount = document.getElementById('driverCount');
const onlineDrivers = document.getElementById('onlineDrivers');

// Menu elements
const mainMenu = document.getElementById('mainMenu');
const passengerBookingMenu = document.getElementById('passengerBookingMenu');
const driverMenu = document.getElementById('driverMenu');
const activeRideMenu = document.getElementById('activeRideMenu');

// Buttons
const bookRideBtn = document.getElementById('bookRideBtn');
const registerDriverBtn = document.getElementById('registerDriverBtn');
const requestRideBtn = document.getElementById('requestRideBtn');
const backToMainBtn = document.getElementById('backToMainBtn');
const toggleDriverStatusBtn = document.getElementById('toggleDriverStatusBtn');
const unregisterDriverBtn = document.getElementById('unregisterDriverBtn');
const acceptRideBtn = document.getElementById('acceptRideBtn');
const rejectRideBtn = document.getElementById('rejectRideBtn');
const arrivedBtn = document.getElementById('arrivedBtn');
const completeRideBtn = document.getElementById('completeRideBtn');
const cancelRideBtn = document.getElementById('cancelRideBtn');

// Utility functions
function formatCoords(x, y) {
    return `${Math.round(x * 10) / 10}, ${Math.round(y * 10) / 10}`;
}

function showStatus(message, type = 'info') {
    statusText.textContent = message;
    statusBar.className = `status-bar show ${type}`;
    setTimeout(() => {
        statusBar.classList.remove('show');
    }, 5000);
}

function updateUI() {
    mainMenu.classList.add('hidden');
    passengerBookingMenu.classList.add('hidden');
    driverMenu.classList.add('hidden');
    activeRideMenu.classList.add('hidden');

    if (isGrabDriver) {
        statusBadge.textContent = 'Tài xế';
        statusBadge.className = 'status-badge driver';
    } else {
        statusBadge.textContent = 'Khách hàng';
        statusBadge.className = 'status-badge passenger';
    }

    if (hasActiveRide || pendingRideRequest) {
        currentView = 'activeRide';
        activeRideMenu.classList.remove('hidden');
        
        if (pendingRideRequest && isGrabDriver) {
            acceptRideBtn.classList.remove('hidden');
            rejectRideBtn.classList.remove('hidden');
            arrivedBtn.classList.add('hidden');
            completeRideBtn.classList.add('hidden');
            currentStatus.textContent = '⏳ Có yêu cầu chuyến xe';
        } else if (hasActiveRide && isGrabDriver) {
            acceptRideBtn.classList.add('hidden');
            rejectRideBtn.classList.add('hidden');
            arrivedBtn.classList.add('hidden');
            completeRideBtn.classList.add('hidden');
            
            if (rideStatus === 'picking_up') {
                currentStatus.textContent = '🚗 Đang đến đón khách (Tự động)';
            } else if (rideStatus === 'in_progress') {
                currentStatus.textContent = '🚕 Đang chở khách (Tự động)';
            } else {
                currentStatus.textContent = '🚗 Đang có chuyến';
            }
        } else if (hasActiveRide && !isGrabDriver) {
            acceptRideBtn.classList.add('hidden');
            rejectRideBtn.classList.add('hidden');
            arrivedBtn.classList.add('hidden');
            completeRideBtn.classList.add('hidden');
            
            if (rideStatus === 'waiting') {
                currentStatus.textContent = '⏳ Đang chờ tài xế chấp nhận';
            } else if (rideStatus === 'picking_up') {
                currentStatus.textContent = '🚗 Tài xế đang đến đón';
            } else if (rideStatus === 'in_progress') {
                currentStatus.textContent = '🚕 Đang trên đường';
            } else {
                currentStatus.textContent = '⏳ Đang chờ tài xế';
            }
        }
    } else if (isGrabDriver) {
        currentView = 'driver';
        driverMenu.classList.remove('hidden');
        currentStatus.textContent = '🟢 Sẵn sàng nhận chuyến';
        toggleDriverStatusBtn.textContent = '🟢 Đang hoạt động';
    } else if (currentView === 'booking') {
        passengerBookingMenu.classList.remove('hidden');
        currentStatus.textContent = '📍 Chọn điểm trả trên bản đồ';
    } else {
        currentView = 'main';
        mainMenu.classList.remove('hidden');
        currentStatus.textContent = '✅ Sẵn sàng';
    }

    if (currentRideData) {
        rideInfo.classList.remove('hidden');
        
        let detailsText = '';
        if (currentRideData.rideId) {
            detailsText += `Mã: ${currentRideData.rideId}\n`;
        }
        if (currentRideData.driverName) {
            detailsText += `Tài xế: ${currentRideData.driverName}\n`;
        }
        if (currentRideData.vehiclePlate) {
            detailsText += `Biển số: ${currentRideData.vehiclePlate}\n`;
        }
        if (currentRideData.passengerName && isGrabDriver) {
            detailsText += `Khách: ${currentRideData.passengerName}\n`;
        }
        if (currentRideData.tripDistance) {
            detailsText += `Quãng đường: ${(currentRideData.tripDistance / 1000).toFixed(1)}km`;
        } else if (currentRideData.distance) {
            detailsText += `Khoảng cách: ${currentRideData.distance}m`;
        }
        
        rideDetails.textContent = detailsText || 'Đang tải...';
        
        if (currentRideData.price) {
            priceInfo.classList.remove('hidden');
            estimatedPrice.textContent = `${currentRideData.price}`;
        }
    } else {
        rideInfo.classList.add('hidden');
        priceInfo.classList.add('hidden');
    }
    
    if (pickupLocation) {
        pickupInfo.classList.remove('hidden');
        pickupLocationEl.textContent = formatCoords(pickupLocation.x, pickupLocation.y);
    } else {
        pickupInfo.classList.add('hidden');
    }
    
    if (dropoffLocation) {
        dropoffInfo.classList.remove('hidden');
        dropoffLocationEl.textContent = formatCoords(dropoffLocation.x, dropoffLocation.y);
    } else {
        dropoffInfo.classList.add('hidden');
    }
}

function setLoading(loading) {
    isLoading = loading;
    const buttons = document.querySelectorAll('.grab-btn');
    buttons.forEach(btn => {
        btn.disabled = loading;
        if (loading && btn.querySelector('.loading-spinner') === null) {
            const spinner = document.createElement('div');
            spinner.className = 'loading-spinner';
            btn.appendChild(spinner);
        } else if (!loading) {
            const spinner = btn.querySelector('.loading-spinner');
            if (spinner) spinner.remove();
        }
    });
}

function sendMessage(action, data = {}) {
    const message = {
        action: action,
        timestamp: Date.now(),
        ...data
    };
    
    console.log('[GRAB DEBUG] Sending message:', JSON.stringify(message));

    if (window.fetch) {
        fetch(`https://lb-phone/GrabApp?t=${Date.now()}`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json; charset=UTF-8',
                'Cache-Control': 'no-cache, no-store, must-revalidate',
                'Pragma': 'no-cache',
                'Expires': '0'
            },
            body: JSON.stringify(message)
        }).then(resp => resp.json()).then(resp => {
            if (action === 'getCurrentLocation' && resp && resp.x && resp.y) {
                currentLocation = { x: resp.x, y: resp.y };
                currentLocationEl.textContent = formatCoords(currentLocation.x, currentLocation.y);
                updateMapLocation(currentLocation.x, currentLocation.y, true);
            }
            
            if (action === 'getGrabDriverStatus' && resp) {
                isGrabDriver = resp.isDriver || false;
                hasActiveRide = resp.hasRide || false;
                updateUI();
            }
            
            if (action === 'toggleUpdateCoords' && resp) {
                isTrackingCoords = data.toggle;
            }
            
            if (action === 'getAllGrabDrivers' && resp && Array.isArray(resp)) {
                addDriverMarkers(resp);
                showStatus(`Hiển thị ${resp.length} tài xế online`);
            }
            
            if (action === 'requestGrabRide' && resp) {
                setLoading(false);
                if (resp.success) {
                    hasActiveRide = true;
                    currentRideData = resp;
                    rideStatus = resp.status || 'waiting';
                    
                    if (dropoffLocation) {
                        currentRideData.dropoffCoords = dropoffLocation;
                    }
                    if (pickupLocation) {
                        currentRideData.pickupCoords = pickupLocation;
                    }
                    
                    updateUI();
                    showStatus(`Đã gửi yêu cầu! Mã chuyến: ${resp.rideId}`, 'success');
                } else {
                    showStatus(resp.message || 'Không tìm thấy tài xế gần bạn', 'error');
                    if (dropoffMarker && map.hasLayer(dropoffMarker)) {
                        map.removeLayer(dropoffMarker);
                        dropoffMarker = null;
                    }
                    dropoffLocation = null;
                    pickupLocation = null;
                }
            }
            
            if (action === 'toggleGrabDriver' && resp) {
                setLoading(false);
                isGrabDriver = resp.status;
                hasActiveRide = resp.hasRide || false;
                updateUI();
                if (currentLocation.x !== 0 && currentLocation.y !== 0) {
                    updateMapLocation(currentLocation.x, currentLocation.y, false);
                }
                showStatus(isGrabDriver ? 'Đã đăng ký làm tài xế!' : 'Đã hủy đăng ký tài xế!');
            }
            
        }).catch(err => {
            // Silent error handling
        });
    }
}

// Event listeners
bookRideBtn.addEventListener('click', () => {
    currentView = 'booking';
    updateUI();
    sendMessage('getAllGrabDrivers');
});

registerDriverBtn.addEventListener('click', () => {
    setLoading(true);
    sendMessage('toggleGrabDriver');
});

requestRideBtn.addEventListener('click', () => {
    if (isGrabDriver) {
        showStatus('Bạn không thể gọi xe khi đang là tài xế!', 'error');
        return;
    }
    
    if (!currentLocation.x || !currentLocation.y) {
        showStatus('Không xác định được vị trí của bạn!', 'error');
        return;
    }
    
    showStatus('Nhấn vào bản đồ để chọn điểm trả khách', 'info');
    
    const selectDropoff = (e) => {
        dropoffLocation = {
            x: e.latlng.lng,
            y: e.latlng.lat
        };
        
        createDropoffMarker(dropoffLocation.x, dropoffLocation.y);
        map.off('click', selectDropoff);
        
        setLoading(true);
        showStatus('Đang tìm tài xế...');
        
        pickupLocation = { ...currentLocation };
        
        console.log('[GRAB DEBUG] Sending request with:', {
            pickupCoords: pickupLocation,
            dropoffCoords: dropoffLocation
        });
        
        sendMessage('requestGrabRide', {
            pickupCoords: pickupLocation,
            dropoffCoords: dropoffLocation
        });
    };
    
    map.on('click', selectDropoff);
});

backToMainBtn.addEventListener('click', () => {
    currentView = 'main';
    updateUI();
    clearDriverMarkers();
    cleanupRideMarkers();
});

toggleDriverStatusBtn.addEventListener('click', () => {
    setLoading(true);
    sendMessage('toggleGrabDriver');
});

unregisterDriverBtn.addEventListener('click', () => {
    setLoading(true);
    sendMessage('toggleGrabDriver');
});

acceptRideBtn.addEventListener('click', () => {
    if (pendingRideRequest && pendingRideRequest.rideId) {
        sendMessage('acceptGrabRide', { rideId: pendingRideRequest.rideId });
        pendingRideRequest = null;
        hasActiveRide = true;
        rideStatus = 'picking_up';
        updateUI();
        showStatus('Đã chấp nhận chuyến xe! Tự động đến điểm đón.', 'success');
    }
});

rejectRideBtn.addEventListener('click', () => {
    if (pendingRideRequest && pendingRideRequest.rideId) {
        sendMessage('rejectGrabRide', { rideId: pendingRideRequest.rideId });
        pendingRideRequest = null;
        currentRideData = null;
        updateUI();
        showStatus('Đã từ chối chuyến xe', 'info');
    }
});

cancelRideBtn.addEventListener('click', () => {
    if (currentRideData && currentRideData.rideId) {
        sendMessage('cancelGrabRide', { rideId: currentRideData.rideId });
    } else if (pendingRideRequest && pendingRideRequest.rideId) {
        sendMessage('rejectGrabRide', { rideId: pendingRideRequest.rideId });
    }
    hasActiveRide = false;
    pendingRideRequest = null;
    currentRideData = null;
    rideStatus = null;
    updateUI();
    cleanupRideMarkers();
    showStatus('Đã hủy chuyến xe!');
});

// Listen for messages from parent
window.addEventListener('message', (event) => {
    const data = event.data.data || event.data;
    const action = event.data.action || event.data.type;

    switch (action) {
        case 'grab:updateCoords':
            const newX = parseFloat(data.x);
            const newY = parseFloat(data.y);
            
            currentLocation = { x: newX, y: newY };
            currentLocationEl.textContent = formatCoords(currentLocation.x, currentLocation.y);
            
            updateMapLocation(currentLocation.x, currentLocation.y, isFollowingPlayer);               
            currentLocationEl.style.display = 'none';
            currentLocationEl.offsetHeight;
            currentLocationEl.style.display = '';
            break;

        case 'getCurrentLocationResponse':
            if (data && data.x && data.y) {
                currentLocation = { x: data.x, y: data.y };
                currentLocationEl.textContent = formatCoords(currentLocation.x, currentLocation.y);
                updateMapLocation(currentLocation.x, currentLocation.y, true);
            }
            break;
            
        case 'grab:updateDriverStatus':
            isGrabDriver = data.isDriver;
            hasActiveRide = data.hasRide || false;
            setLoading(false);
            updateUI();
            if (currentLocation.x !== 0 && currentLocation.y !== 0) {
                updateMapLocation(currentLocation.x, currentLocation.y, false);
            }
            showStatus(isGrabDriver ? 'Đã bật chế độ tài xế!' : 'Đã tắt chế độ tài xế!');
            break;

        case 'grab:newRideRequest':
            if (isGrabDriver) {
                pendingRideRequest = data;
                currentRideData = data;
                updateUI();
                showStatus(`Yêu cầu mới! Khách: ${data.passengerName} - Quãng đường: ${(data.tripDistance / 1000).toFixed(1)}km`, 'info');
            }
            break;

        case 'grab:rideAccepted':
            hasActiveRide = true;
            currentRideData = { ...currentRideData, ...data };
            rideStatus = data.status || 'picking_up';
            setLoading(false);
            
            if (data.dropoffCoords) {
                dropoffLocation = data.dropoffCoords;
            }
            if (data.pickupCoords) {
                pickupLocation = data.pickupCoords;
            }
            
            updateUI();
            showStatus(`Tài xế ${data.driverName} (${data.vehiclePlate}) đã chấp nhận!`, 'success');
            
            if (data.driverCoords) {
                updateDriverMarker(data.driverCoords.x, data.driverCoords.y, data.vehiclePlate);
            }
            
            if (data.dropoffCoords && !isGrabDriver) {
                createDropoffMarker(data.dropoffCoords.x, data.dropoffCoords.y);
            }
            break;

        case 'grab:driverLocationUpdate':
            if (data.x && data.y) {
                updateDriverMarker(data.x, data.y, data.vehiclePlate);
            }
            break;

        case 'grab:updateRideStatus':
            rideStatus = data.status;
            if (data.message) {
                showStatus(data.message, 'info');
            }
            updateUI();
            break;

        case 'grab:arrivedAtPickup':
            rideStatus = 'in_progress';
            showStatus('Đã đến điểm đón! Đang chuyển sang điểm trả khách...', 'success');
            updateUI();
            break;

        case 'grab:driverArrived':
            rideStatus = 'in_progress';
            showStatus('Tài xế đã đến! Chuyến đi bắt đầu.', 'success');
            if (driverMarker && map.hasLayer(driverMarker)) {
                map.removeLayer(driverMarker);
                driverMarker = null;
            }
            if (dropoffLocation && !dropoffMarker) {
                createDropoffMarker(dropoffLocation.x, dropoffLocation.y);
            }
            updateUI();
            break;

        case 'grab:rideCompleted':
            // PHẦN ĐÃ SỬA - Reset TẤT CẢ trạng thái về ban đầu
            hasActiveRide = false;
            pendingRideRequest = null;
            currentRideData = null;
            rideStatus = null;
            pickupLocation = null;
            dropoffLocation = null;
            
            // Cleanup tất cả markers
            cleanupRideMarkers();
            
            // Hiển thị thông báo hoàn thành
            const completedMsg = data.price ? 
                `Hoàn thành chuyến xe! Chi phí: $${data.price}` : 
                `Hoàn thành chuyến xe!`;
            showStatus(completedMsg, 'success');
            
            // Hiển thị giá tạm thời
            if (data.price) {
                estimatedPrice.textContent = `${data.price}`;
                priceInfo.classList.remove('hidden');
                
                // Ẩn giá sau 5 giây
                setTimeout(() => {
                    priceInfo.classList.add('hidden');
                }, 5000);
            }
            
            // Reset về view chính
            currentView = 'main';
            updateUI();
            break;

        case 'grab:rideCancelled':
            hasActiveRide = false;
            pendingRideRequest = null;
            currentRideData = null;
            rideStatus = 'cancelled';
            setLoading(false);
            updateUI();
            showStatus(data.reason || 'Chuyến xe đã bị hủy!', 'error');
            cleanupRideMarkers();
            break;

        case 'grab:rideRejected':
            pendingRideRequest = null;
            currentRideData = null;
            updateUI();
            showStatus('Đã từ chối chuyến xe', 'info');
            break;

        case 'grab:rideTimeout':
            pendingRideRequest = null;
            currentRideData = null;
            updateUI();
            showStatus('Hết thời gian chấp nhận chuyến', 'error');
            break;

        default:
            break;
    }
});

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    updateUI();

    const mapInitialized = initMap();

    if (mapInitialized) {
        setTimeout(() => {
            sendMessage('getCurrentLocation');
            sendMessage('getGrabDriverStatus');
            sendMessage('toggleUpdateCoords', { toggle: true });
            sendMessage('getAllGrabDrivers');
        }, 300);

        setInterval(() => {
            if (isTrackingCoords) {
                sendMessage('getCurrentLocation');
            }
            if (currentView === 'main' || currentView === 'booking') {
                sendMessage('getAllGrabDrivers');
            }
        }, 5000);
    }

    showStatus('Ứng dụng Grab đã sẵn sàng!');
});

// Cleanup when page unloads
window.addEventListener('beforeunload', () => {
    console.log('Cleaning up coordinate tracking...');
    sendMessage('toggleUpdateCoords', { toggle: false });
});
