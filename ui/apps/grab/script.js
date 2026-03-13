// Global state
let isGrabDriver = false;
let hasActiveRide = false;
let currentLocation = { x: 0, y: 0 };
let isLoading = false;
let map = null;
let currentMarker = null;
let driverMarkers = [];
let isFollowingPlayer = true;
let isTrackingCoords = false;
let currentView = 'main'; // main, booking, driver, activeRide
let pendingRideRequest = null;
let currentRideData = null;

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
    // Rút gọn tọa độ: chỉ hiển thị 1 số thập phân
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
    // Hide all menus first
    mainMenu.classList.add('hidden');
    passengerBookingMenu.classList.add('hidden');
    driverMenu.classList.add('hidden');
    activeRideMenu.classList.add('hidden');

    // Update status badge
    if (isGrabDriver) {
        statusBadge.textContent = 'Tài xế';
        statusBadge.className = 'status-badge driver';
    } else {
        statusBadge.textContent = 'Khách hàng';
        statusBadge.className = 'status-badge passenger';
    }

    // Show appropriate menu based on current view and state
    if (hasActiveRide || pendingRideRequest) {
        currentView = 'activeRide';
        activeRideMenu.classList.remove('hidden');
        
        if (pendingRideRequest && isGrabDriver) {
            acceptRideBtn.classList.remove('hidden');
            rejectRideBtn.classList.remove('hidden');
            arrivedBtn.classList.add('hidden');
            completeRideBtn.classList.add('hidden');
            currentStatus.textContent = 'Có yêu cầu chuyến xe';
        } else if (hasActiveRide && isGrabDriver) {
            acceptRideBtn.classList.add('hidden');
            rejectRideBtn.classList.add('hidden');
            arrivedBtn.classList.remove('hidden');
            completeRideBtn.classList.remove('hidden');
            currentStatus.textContent = 'Đang có chuyến';
        } else if (hasActiveRide && !isGrabDriver) {
            acceptRideBtn.classList.add('hidden');
            rejectRideBtn.classList.add('hidden');
            arrivedBtn.classList.add('hidden');
            completeRideBtn.classList.add('hidden');
            currentStatus.textContent = 'Đang chờ tài xế';
        }
    } else if (isGrabDriver) {
        currentView = 'driver';
        driverMenu.classList.remove('hidden');
        currentStatus.textContent = 'Đang chờ khách';
        toggleDriverStatusBtn.textContent = '🟢 Đang hoạt động';
    } else if (currentView === 'booking') {
        passengerBookingMenu.classList.remove('hidden');
        currentStatus.textContent = 'Chọn điểm đón';
    } else {
        currentView = 'main';
        mainMenu.classList.remove('hidden');
        currentStatus.textContent = 'Sẵn sàng';
    }

    // Update ride info
    if (currentRideData) {
        rideInfo.classList.remove('hidden');
        rideDetails.textContent = `Khoảng cách: ${currentRideData.distance}m`;
        if (currentRideData.price) {
            priceInfo.classList.remove('hidden');
            estimatedPrice.textContent = `${currentRideData.price}`;
        }
    } else {
        rideInfo.classList.add('hidden');
        priceInfo.classList.add('hidden');
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

// Enhanced sendMessage function with NUI callback support
function sendMessage(action, data = {}) {
    const message = {
        action: action,
        timestamp: Date.now(),
        ...data
    };

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
            // Handle specific responses
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
                    currentRideData = resp.rideData;
                    updateUI();
                    showStatus('Đã gửi yêu cầu! Đang chờ tài xế chấp nhận...', 'success');
                } else {
                    showStatus(resp.message || 'Không tìm thấy tài xế gần bạn', 'error');
                }
            }
            
            if (action === 'toggleGrabDriver' && resp) {
                setLoading(false);
                isGrabDriver = resp.status;
                hasActiveRide = resp.hasRide || false;
                updateUI();
                // Cập nhật marker ngay lập tức với màu mới
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
    // Load và hiển thị tất cả tài xế online
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
    setLoading(true);
    showStatus('Đang tìm tài xế...');
    sendMessage('requestGrabRide');
});

backToMainBtn.addEventListener('click', () => {
    currentView = 'main';
    updateUI();
    // Xóa tất cả driver markers khi quay lại main
    clearDriverMarkers();
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
    if (pendingRideRequest) {
        sendMessage('acceptGrabRide', { rideId: pendingRideRequest.rideId });
        pendingRideRequest = null;
        hasActiveRide = true;
        updateUI();
    }
});

rejectRideBtn.addEventListener('click', () => {
    if (pendingRideRequest) {
        sendMessage('rejectGrabRide', { rideId: pendingRideRequest.rideId });
        pendingRideRequest = null;
        updateUI();
    }
});

arrivedBtn.addEventListener('click', () => {
    if (currentRideData) {
        sendMessage('arrivedAtPickup', { rideId: currentRideData.rideId });
    }
});

completeRideBtn.addEventListener('click', () => {
    if (currentRideData) {
        sendMessage('completeGrabRide', { rideId: currentRideData.rideId });
        hasActiveRide = false;
        currentRideData = null;
        updateUI();
        showStatus('Đã hoàn thành chuyến xe!', 'success');
    }
});

cancelRideBtn.addEventListener('click', () => {
    if (currentRideData) {
        sendMessage('cancelGrabRide', { rideId: currentRideData.rideId });
    } else if (pendingRideRequest) {
        sendMessage('rejectGrabRide', { rideId: pendingRideRequest.rideId });
    }
    hasActiveRide = false;
    pendingRideRequest = null;
    currentRideData = null;
    updateUI();
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
            // Force DOM refresh
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
            // Cập nhật marker ngay lập tức với màu mới
            if (currentLocation.x !== 0 && currentLocation.y !== 0) {
                updateMapLocation(currentLocation.x, currentLocation.y, false);
            }
            showStatus(isGrabDriver ? 'Đã bật chế độ tài xế!' : 'Đã tắt chế độ tài xế!');
            break;

        case 'grab:rideRequest':
            if (isGrabDriver) {
                pendingRideRequest = data;
                updateUI();
                showStatus(`Yêu cầu chuyến xe mới! Khoảng cách: ${data.distance}m`, 'info');
            }
            break;

        case 'grab:rideAccepted':
            hasActiveRide = true;
            currentRideData = data;
            setLoading(false);
            updateUI();
            showStatus('Tài xế đã chấp nhận! Đang trên đường đến...', 'success');
            break;

        case 'grab:driverArrived':
            showStatus('Tài xế đã đến! Chúc bạn đi đường an toàn.', 'success');
            break;

        case 'grab:rideCompleted':
            hasActiveRide = false;
            updateUI();
            showStatus(`Hoàn thành chuyến xe! Chi phí: ${data.price}`, 'success');
            if (data.price) {
                estimatedPrice.textContent = `${data.price}`;
                priceInfo.classList.remove('hidden');
            }
            break;

        case 'grab:rideCancelled':
            hasActiveRide = false;
            pendingRideRequest = null;
            currentRideData = null;
            setLoading(false);
            updateUI();
            showStatus(data.reason || 'Chuyến xe đã bị hủy!', 'error');
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
            // Load tất cả tài xế online khi mở app
            sendMessage('getAllGrabDrivers');
        }, 300);

        // Heartbeat để keep connection fresh
        setInterval(() => {
            if (isTrackingCoords) {
                sendMessage('getCurrentLocation');
            }
            // Refresh driver list mỗi 10 giây
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