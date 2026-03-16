// Grab App - Simple Layout
const state = {
    isDriver: false,
    hasRide: false,
    location: { x: 0, y: 0 },
    pickup: null,
    dropoff: null,
    rideData: null,
    rideStatus: null,
    pendingRequest: null,
    view: 'main',
    isFollowing: true,
    isTracking: false
};

let map = null;
const markers = { current: null, driver: null, pickup: null, dropoff: null, taxis: [] };

const MAP_CONFIG = {
    image: [16384, 24576],
    topLeft: [-4140, 8400],
    bottomRight: [4860, -5100],
    tileServer: "https://assets.loaf-scripts.com/map-tiles/gtav/main/{layer}/{z}/{x}/{y}.jpg",
    defaultCenter: [1650, 1650],
    defaultZoom: 3
};

// DOM Cache
const $ = (id) => document.getElementById(id);
const DOM = {
    statusBar: $('statusBar'), statusText: $('statusText'),
    currentLocationEl: $('currentLocation'),
    pickupLocationEl: $('pickupLocation'), dropoffLocationEl: $('dropoffLocation'),
    pickupInfo: $('pickupInfo'), dropoffInfo: $('dropoffInfo'),
    priceInfo: $('priceInfo'), estimatedPrice: $('estimatedPrice'),
    rideInfo: $('rideInfo'), rideDetails: $('rideDetails'),
    driverCount: $('driverCount'), onlineDrivers: $('onlineDrivers'),
    
    // Main menu and panels
    mainMenu: $('mainMenu'),
    passengerBtn: $('passengerBtn'), driverBtn: $('driverBtn'),
    passengerPanel: $('passengerPanel'), driverPanel: $('driverPanel'),
    backToMainFromPassenger: $('backToMainFromPassenger'), backToMainFromDriver: $('backToMainFromDriver'),
    passengerStatus: $('passengerStatus'), driverStatus: $('driverStatus'),
    
    // Passenger menus
    passengerBookingMenu: $('passengerBookingMenu'), requestRideMenu: $('requestRideMenu'),
    passengerActiveRideMenu: $('passengerActiveRideMenu'),
    
    // Driver menus
    driverRegisterMenu: $('driverRegisterMenu'), driverMenu: $('driverMenu'),
    driverActiveRideMenu: $('driverActiveRideMenu'),
    
    // Buttons
    bookRideBtn: $('bookRideBtn'), registerDriverBtn: $('registerDriverBtn'),
    requestRideBtn: $('requestRideBtn'), backToBookingBtn: $('backToBookingBtn'),
    toggleDriverStatusBtn: $('toggleDriverStatusBtn'), unregisterDriverBtn: $('unregisterDriverBtn'),
    acceptRideBtn: $('acceptRideBtn'), rejectRideBtn: $('rejectRideBtn'),
    cancelRideBtn: $('cancelRideBtn'), cancelDriverRideBtn: $('cancelDriverRideBtn')
};

// Utilities
const utils = {
    formatCoords: (x, y) => `${Math.round(x * 10) / 10}, ${Math.round(y * 10) / 10}`,

    showStatus: (msg, type = 'info') => {
        DOM.statusText.textContent = msg;
        DOM.statusBar.className = `status-bar show ${type}`;
        setTimeout(() => DOM.statusBar.classList.remove('show'), 5000);
    },

    setLoading: (loading) => {
        document.querySelectorAll('.grab-btn').forEach(btn => {
            btn.disabled = loading;
            const spinner = btn.querySelector('.loading-spinner');
            if (loading && !spinner) {
                btn.appendChild(Object.assign(document.createElement('div'), { className: 'loading-spinner' }));
            } else if (!loading && spinner) {
                spinner.remove();
            }
        });
    },

    hideAllMenus: () => {
        // Hide passenger menus
        [DOM.passengerBookingMenu, DOM.requestRideMenu, DOM.passengerActiveRideMenu].forEach(m => m.classList.add('hidden'));
        // Hide driver menus
        [DOM.driverRegisterMenu, DOM.driverMenu, DOM.driverActiveRideMenu].forEach(m => m.classList.add('hidden'));
    },

    showMainMenu: () => {
        DOM.mainMenu.classList.remove('hidden');
        DOM.passengerPanel.classList.remove('show');
        DOM.driverPanel.classList.remove('show');
    },

    showPassengerPanel: () => {
        console.log('Showing passenger panel');
        DOM.mainMenu.classList.add('hidden');
        DOM.passengerPanel.classList.add('show');
        DOM.driverPanel.classList.remove('show');
        console.log('Passenger panel classes:', DOM.passengerPanel.className);
    },

    showDriverPanel: () => {
        console.log('Showing driver panel');
        DOM.mainMenu.classList.add('hidden');
        DOM.driverPanel.classList.add('show');
        DOM.passengerPanel.classList.remove('show');
        console.log('Driver panel classes:', DOM.driverPanel.className);
    }
};

// Map Functions
const mapFn = {
    createCRS: (cfg) => {
        const { image, topLeft, bottomRight } = cfg;
        const maxZoom = Math.ceil(Math.log(Math.max(image[0], image[1]) / 256) / Math.log(2));
        const [gw, gh] = [bottomRight[0] - topLeft[0], bottomRight[1] - topLeft[1]];
        if (gw === 0 || gh === 0) return L.CRS.Simple;

        const scale = Math.pow(2, maxZoom);
        const [sx, sy] = [image[0] / (gw * scale), image[1] / (gh * scale)];
        const [ox, oy] = [-sx * topLeft[0], -sy * topLeft[1]];

        return L.extend({}, L.CRS.Simple, {
            projection: L.Projection.LonLat,
            transformation: new L.Transformation(sx, ox, sy, oy),
            scale: (z) => Math.pow(2, z),
            zoom: (s) => Math.log(s) / Math.LN2
        });
    },

    init: () => {
        try {
            map = L.map('map', {
                crs: mapFn.createCRS(MAP_CONFIG),
                center: MAP_CONFIG.defaultCenter,
                zoom: MAP_CONFIG.defaultZoom,
                zoomControl: true,
                attributionControl: false,
                maxBounds: [MAP_CONFIG.topLeft, MAP_CONFIG.bottomRight],
                maxBoundsViscosity: 1.0
            });

            const createLayer = (layer) => L.tileLayer(
                MAP_CONFIG.tileServer.replace('{layer}', layer),
                {
                    maxZoom: 6, minZoom: 1, tileSize: 256, zoomOffset: 0,
                    noWrap: true, bounds: [MAP_CONFIG.topLeft, MAP_CONFIG.bottomRight]
                }
            );

            const layers = {
                "Bản đồ vệ tinh (Print)": createLayer('print')
            };

            layers["Bản đồ vệ tinh (Print)"].addTo(map);
            L.control.layers(layers).addTo(map);
            map.on('dragstart', () => state.isFollowing = false);
            setTimeout(() => map.invalidateSize(), 100);

            if (state.location.x !== 0) {
                mapFn.updateLoc(state.location.x, state.location.y);
            }
            return true;
        } catch (e) {
            return false;
        }
    },

    updateLoc: (x, y, follow = true) => {
        if (!map) return;

        const coords = [Math.round(y), Math.round(x)];
        
        // Chỉ di chuyển map nếu follow = true và đang theo dõi
        if (follow && state.isFollowing) {
            map.setView(coords, map.getZoom());
        }

        // Cập nhật vị trí trong state
        state.location = { x: x, y: y };

        // Xóa marker cũ và tạo marker mới
        if (markers.current) map.removeLayer(markers.current);

        const color = state.isDriver ? 'green' : 'blue';
        const icon = L.icon({
            iconUrl: `https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-${color}.png?t=${Date.now()}`,
            shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-shadow.png',
            iconSize: [25, 41], iconAnchor: [12, 41], popupAnchor: [1, -34], shadowSize: [41, 41]
        });

        const label = state.isDriver ? 'Vị trí tài xế (Bạn)' : 'Vị trí của bạn';
        markers.current = L.marker(coords, { icon, riseOnHover: true, title: label })
            .addTo(map).bindPopup(label);
        markers.current.on('click', () => state.isFollowing = true);
        
        // Force map refresh
        setTimeout(() => map.invalidateSize(), 50);
    }
};

// Route Functions (simplified)
const routeFn = {
    clearAll: () => {
        // Clear any existing routes if needed in future
    }
};

// Marker Functions
const markerFn = {
    createIcon: (color, size = [25, 41]) => L.icon({
        iconUrl: `https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-${color}.png`,
        shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-shadow.png',
        iconSize: size,
        iconAnchor: [size[0] / 2, size[1]],
        popupAnchor: [1, -size[1] + 7],
        shadowSize: [size[1], size[1]]
    }),

    remove: (type) => {
        if (markers[type] && map.hasLayer(markers[type])) {
            map.removeLayer(markers[type]);
            markers[type] = null;
        }
    },

    create: (type, x, y, label) => {
        if (!map) return;
        markerFn.remove(type);
        const colors = { driver: 'blue', pickup: 'green', dropoff: 'orange' };
        markers[type] = L.marker([Math.round(y), Math.round(x)], {
            icon: markerFn.createIcon(colors[type])
        }).addTo(map).bindPopup(label);
    },

    clearTaxis: () => {
        markers.taxis.forEach(m => map.hasLayer(m) && map.removeLayer(m));
        markers.taxis = [];
    },

    addTaxis: (drivers) => {
        markerFn.clearTaxis();
        if (!drivers || !Array.isArray(drivers)) return;

        drivers.forEach(d => {
            const [x, y] = [d.coords?.x || d.x, d.coords?.y || d.y];
            if (!x || !y) return;

            const m = L.marker([Math.round(y), Math.round(x)], {
                icon: markerFn.createIcon(d.busy ? 'red' : 'green', [20, 33])
            }).addTo(map).bindPopup(
                `<strong>🚗 Tài xế Grab</strong><br/>` +
                `Khoảng cách: ${d.distance || 0}m<br/>` +
                `Trạng thái: ${d.busy ? '🔴 Bận' : '🟢 Rảnh'}`
            );
            markers.taxis.push(m);
        });

        DOM.driverCount.classList.remove('hidden');
        DOM.onlineDrivers.textContent = drivers.length;
    },

    cleanup: () => {
        // Chỉ xóa markers pickup/dropoff và driver, KHÔNG xóa vị trí hiện tại
        ['driver', 'pickup', 'dropoff'].forEach(markerFn.remove);
        state.pickup = null;
        state.dropoff = null;
        DOM.pickupInfo.classList.add('hidden');
        DOM.dropoffInfo.classList.add('hidden');
    }
};

// UI Functions
const ui = {
    update: () => {
        utils.hideAllMenus();
        
        // Update status displays
        if (state.isDriver) {
            DOM.driverStatus.textContent = '🟢 Đã đăng ký';
            DOM.passengerStatus.textContent = '🔴 Chế độ tài xế';
        } else {
            DOM.driverStatus.textContent = '🔴 Chưa đăng ký';
            DOM.passengerStatus.textContent = '✅ Sẵn sàng';
        }

        // Show appropriate menus based on current state
        if (state.hasRide || state.pendingRequest) {
            if (state.isDriver) {
                DOM.driverActiveRideMenu.classList.remove('hidden');
                ui.updateDriverRide();
            } else {
                DOM.passengerActiveRideMenu.classList.remove('hidden');
            }
        } else if (state.isDriver) {
            DOM.driverMenu.classList.remove('hidden');
            DOM.toggleDriverStatusBtn.textContent = '🟢 Đang hoạt động';
        } else if (state.view === 'booking') {
            DOM.requestRideMenu.classList.remove('hidden');
            DOM.passengerStatus.textContent = '📍 Chọn điểm trả trên bản đồ';
        } else {
            // Show main menus
            if (state.isDriver) {
                DOM.driverMenu.classList.remove('hidden');
            } else {
                DOM.passengerBookingMenu.classList.remove('hidden');
            }
            
            // Show driver registration if not registered
            if (!state.isDriver) {
                DOM.driverRegisterMenu.classList.remove('hidden');
            }
        }

        ui.updateInfo();
    },

    updateDriverRide: () => {
        [DOM.acceptRideBtn, DOM.rejectRideBtn].forEach(b => b.classList.add('hidden'));

        if (state.pendingRequest && state.isDriver) {
            DOM.acceptRideBtn.classList.remove('hidden');
            DOM.rejectRideBtn.classList.remove('hidden');
            DOM.driverStatus.textContent = '⏳ Có yêu cầu chuyến xe';
        } else if (state.hasRide) {
            DOM.driverStatus.textContent = '🚗 Đang có chuyến';
        }
    },

    updateInfo: () => {
        if (!state.rideData) {
            DOM.rideInfo.classList.add('hidden');
            DOM.priceInfo.classList.add('hidden');
            return;
        }

        DOM.rideInfo.classList.remove('hidden');
        const details = [];
        const d = state.rideData;

        if (d.rideId) details.push(`Mã: ${d.rideId}`);
        if (d.driverName) details.push(`Tài xế: ${d.driverName}`);
        if (d.vehiclePlate) details.push(`Biển số: ${d.vehiclePlate}`);
        if (d.passengerName && state.isDriver) details.push(`Khách: ${d.passengerName}`);
        if (d.tripDistance) details.push(`Quãng đường: ${(d.tripDistance / 1000).toFixed(1)}km`);
        else if (d.distance) details.push(`Khoảng cách: ${d.distance}m`);

        DOM.rideDetails.textContent = details.join('\n') || 'Đang tải...';

        if (d.price) {
            DOM.priceInfo.classList.remove('hidden');
            DOM.estimatedPrice.textContent = d.price;
        }

        // Update location info
        if (state.pickup) {
            DOM.pickupInfo.classList.remove('hidden');
            DOM.pickupLocationEl.textContent = utils.formatCoords(state.pickup.x, state.pickup.y);
        } else {
            DOM.pickupInfo.classList.add('hidden');
        }

        if (state.dropoff) {
            DOM.dropoffInfo.classList.remove('hidden');
            DOM.dropoffLocationEl.textContent = utils.formatCoords(state.dropoff.x, state.dropoff.y);
        } else {
            DOM.dropoffInfo.classList.add('hidden');
        }
    }
};

// Communication
const comm = {
    send: (action, data = {}) => {
        if (!window.fetch) return;

        fetch(`https://lb-phone/GrabApp?t=${Date.now()}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8', 'Cache-Control': 'no-cache' },
            body: JSON.stringify({ action, timestamp: Date.now(), ...data })
        })
            .then(r => r.json())
            .then(r => comm.handleResp(action, r, data))
            .catch(() => { });
    },

    handleResp: (action, resp, data) => {
        const handlers = {
            getCurrentLocation: () => {
                if (resp?.x && resp?.y) {
                    state.location = { x: resp.x, y: resp.y };
                    DOM.currentLocationEl.textContent = utils.formatCoords(resp.x, resp.y);
                    mapFn.updateLoc(resp.x, resp.y, true);
                }
            },

            getGrabDriverStatus: () => {
                if (resp) {
                    state.isDriver = resp.isDriver || false;
                    state.hasRide = resp.hasRide || false;
                    ui.update();
                    
                    // Luôn hiển thị tất cả tài xế khi mở app (cả khách hàng và tài xế)
                    comm.send('getAllGrabDrivers');
                }
            },

            getAllGrabDrivers: () => {
                if (resp && Array.isArray(resp)) {
                    markerFn.addTaxis(resp);
                    utils.showStatus(`Hiển thị ${resp.length} tài xế online`);
                }
            },

            requestGrabRide: () => {
                utils.setLoading(false);
                if (resp.success) {
                    state.hasRide = true;
                    state.rideData = { ...resp, dropoffCoords: state.dropoff, pickupCoords: state.pickup };
                    state.rideStatus = resp.status || 'waiting';
                    ui.update();
                    utils.showStatus(`Đã gửi yêu cầu! Mã chuyến: ${resp.rideId}`, 'success');
                } else {
                    utils.showStatus(resp.message || 'Không tìm thấy tài xế gần bạn', 'error');
                    markerFn.remove('dropoff');
                    state.dropoff = null;
                    state.pickup = null;
                }
            },

            toggleGrabDriver: () => {
                utils.setLoading(false);
                state.isDriver = resp.status;
                state.hasRide = resp.hasRide || false;
                ui.update();
                if (state.location.x !== 0) mapFn.updateLoc(state.location.x, state.location.y, false);
                utils.showStatus(state.isDriver ? 'Đã đăng ký làm tài xế!' : 'Đã hủy đăng ký tài xế!');
                
                // Luôn hiển thị tất cả tài xế (cả khi đăng ký và hủy đăng ký)
                comm.send('getAllGrabDrivers');
            }
        };

        handlers[action]?.();
    },

    handleMsg: (e) => {
        const data = e.data.data || e.data;
        const action = e.data.action || e.data.type;

        const handlers = {
            'grab:updateCoords': () => {
                const newX = parseFloat(data.x);
                const newY = parseFloat(data.y);
                
                // Chỉ cập nhật nếu vị trí thực sự thay đổi
                if (Math.abs(state.location.x - newX) > 0.5 || Math.abs(state.location.y - newY) > 0.5) {
                    state.location = { x: newX, y: newY };
                    DOM.currentLocationEl.textContent = utils.formatCoords(newX, newY);
                    mapFn.updateLoc(newX, newY, state.isFollowing);
                }
            },

            'grab:updateDriverStatus': () => {
                state.isDriver = data.isDriver;
                state.hasRide = data.hasRide || false;
                utils.setLoading(false);
                ui.update();
                if (state.location.x !== 0) mapFn.updateLoc(state.location.x, state.location.y, false);
                utils.showStatus(state.isDriver ? 'Đã bật chế độ tài xế!' : 'Đã tắt chế độ tài xế!');
                
                // Luôn hiển thị tất cả tài xế
                comm.send('getAllGrabDrivers');
            },

            'grab:rideAccepted': () => {
                state.hasRide = true;
                state.rideData = { ...state.rideData, ...data };
                state.rideStatus = data.status || 'picking_up';
                utils.setLoading(false);

                if (data.dropoffCoords) state.dropoff = data.dropoffCoords;
                if (data.pickupCoords) state.pickup = data.pickupCoords;
                
                // Hiển thị markers khác nhau cho khách hàng và tài xế
                if (state.isDriver) {
                    // Tài xế thấy điểm đón khách và điểm đến
                    if (data.pickupCoords) {
                        markerFn.create('pickup', data.pickupCoords.x, data.pickupCoords.y, '📍 Điểm đón khách');
                    }
                    if (data.dropoffCoords) {
                        markerFn.create('dropoff', data.dropoffCoords.x, data.dropoffCoords.y, '🏁 Điểm đến');
                    }
                } else {
                    // Khách hàng thấy vị trí tài xế và điểm đến
                    if (data.driverCoords) {
                        markerFn.create('driver', data.driverCoords.x, data.driverCoords.y, '🚗 Tài xế');
                    }
                    if (data.dropoffCoords) {
                        markerFn.create('dropoff', data.dropoffCoords.x, data.dropoffCoords.y, '🏁 Điểm trả');
                    }
                }

                ui.update();
                utils.showStatus(`Tài xế ${data.driverName} (${data.vehiclePlate}) đã chấp nhận!`, 'success');
            },

            'grab:driverLocationUpdate': () => {
                if (data.x && data.y) markerFn.create('driver', data.x, data.y, '🚗 Tài xế');
            },

            'grab:driverArrived': () => {
                state.rideStatus = 'in_progress';
                utils.showStatus('Tài xế đã đến! Chuyến đi bắt đầu.', 'success');
                markerFn.remove('driver');
                if (state.dropoff && !markers.dropoff) {
                    markerFn.create('dropoff', state.dropoff.x, state.dropoff.y, '🏁 Điểm trả');
                }
                ui.update();
            },

            'grab:rideCompleted': () => {
                state.hasRide = false;
                state.pendingRequest = null;
                state.rideData = null;
                state.rideStatus = null;
                state.pickup = null;
                state.dropoff = null;
                markerFn.cleanup();

                const msg = data.price ? `Hoàn thành chuyến xe! Chi phí: ${data.price}` : 'Hoàn thành chuyến xe!';
                utils.showStatus(msg, 'success');

                if (data.price) {
                    DOM.estimatedPrice.textContent = data.price;
                    DOM.priceInfo.classList.remove('hidden');
                    setTimeout(() => DOM.priceInfo.classList.add('hidden'), 5000);
                }

                state.view = 'main';
                ui.update();
            },

            'grab:rideCancelled': () => {
                state.hasRide = false;
                state.pendingRequest = null;
                state.rideData = null;
                state.rideStatus = 'cancelled';
                utils.setLoading(false);
                ui.update();
                utils.showStatus(data.reason || 'Chuyến xe đã bị hủy!', 'error');
                markerFn.cleanup();
            },

            'grab:rideRequest': () => {
                // Khi có yêu cầu chuyến xe mới cho tài xế
                if (state.isDriver) {
                    state.pendingRequest = {
                        rideId: data.rideId,
                        pickupCoords: data.pickupCoords || data.passengerCoords,
                        dropoffCoords: data.dropoffCoords,
                        passengerName: data.passengerName,
                        distance: data.distance
                    };
                    state.rideData = { ...data };
                    ui.update();
                    utils.showStatus(`Có yêu cầu chuyến xe từ ${data.passengerName || 'khách hàng'}!`, 'info');
                }
            },

            'grab:newRideRequest': () => {
                // Alias cho grab:rideRequest (nếu server gửi event này)
                if (state.isDriver) {
                    state.pendingRequest = {
                        rideId: data.rideId,
                        pickupCoords: data.pickupCoords || data.passengerCoords,
                        dropoffCoords: data.dropoffCoords,
                        passengerName: data.passengerName,
                        distance: data.distance
                    };
                    state.rideData = { ...data };
                    ui.update();
                    utils.showStatus(`Có yêu cầu chuyến xe từ ${data.passengerName || 'khách hàng'}!`, 'info');
                }
            }
        };

        handlers[action]?.();
    }
};

// Event Setup
const setupEvents = () => {
    // Main menu buttons
    DOM.passengerBtn.addEventListener('click', () => {
        console.log('Passenger button clicked');
        utils.showPassengerPanel();
        ui.update();
        // Cập nhật vị trí khi chuyển sang chế độ khách hàng
        comm.send('getCurrentLocation');
    });

    DOM.driverBtn.addEventListener('click', () => {
        console.log('Driver button clicked');
        utils.showDriverPanel();
        ui.update();
        // Cập nhật vị trí khi chuyển sang chế độ tài xế
        comm.send('getCurrentLocation');
    });

    // Back buttons
    DOM.backToMainFromPassenger.addEventListener('click', () => {
        utils.showMainMenu();
        state.view = 'main';
        // Giữ hiển thị tài xế cho cả khách hàng và tài xế
        // markerFn.clearTaxis(); // Bỏ dòng này
        // Không xóa gì cả - giữ nguyên vị trí hiện tại và tài xế
    });

    DOM.backToMainFromDriver.addEventListener('click', () => {
        utils.showMainMenu();
        state.view = 'main';
        // Giữ hiển thị tài xế cho cả khách hàng và tài xế
        // Không xóa gì cả - giữ nguyên vị trí hiện tại và tài xế
    });

    // Passenger events
    DOM.bookRideBtn.addEventListener('click', () => {
        state.view = 'booking';
        ui.update();
        comm.send('getAllGrabDrivers');
    });

    DOM.requestRideBtn.addEventListener('click', () => {
        if (state.isDriver) return utils.showStatus('Bạn không thể gọi xe khi đang là tài xế!', 'error');
        if (!state.location.x || !state.location.y) {
            return utils.showStatus('Không xác định được vị trí của bạn!', 'error');
        }

        utils.showStatus('Nhấn vào bản đồ để chọn điểm trả khách', 'info');

        const selectDropoff = (e) => {
            state.dropoff = { x: e.latlng.lng, y: e.latlng.lat };
            markerFn.create('dropoff', state.dropoff.x, state.dropoff.y, '🏁 Điểm trả');
            map.off('click', selectDropoff);

            utils.setLoading(true);
            utils.showStatus('Đang tìm tài xế...');
            state.pickup = { ...state.location };
            comm.send('requestGrabRide', { pickupCoords: state.pickup, dropoffCoords: state.dropoff });
        };

        map.on('click', selectDropoff);
    });

    DOM.backToBookingBtn.addEventListener('click', () => {
        state.view = 'main';
        ui.update();
        // Giữ hiển thị tài xế cho cả khách hàng và tài xế
        // Không xóa pickup/dropoff - để người dùng thấy chuyến xe
    });

    DOM.cancelRideBtn.addEventListener('click', () => {
        const rideId = state.rideData?.rideId || state.pendingRequest?.rideId;
        if (rideId) {
            comm.send(state.rideData ? 'cancelGrabRide' : 'rejectGrabRide', { rideId });
        }
        state.hasRide = false;
        state.pendingRequest = null;
        state.rideData = null;
        state.rideStatus = null;
        ui.update();
        markerFn.cleanup(); // Chỉ xóa khi hủy chuyến
        utils.showStatus('Đã hủy chuyến xe!');
    });

    // Driver events
    DOM.registerDriverBtn.addEventListener('click', () => {
        utils.setLoading(true);
        comm.send('toggleGrabDriver');
    });

    DOM.toggleDriverStatusBtn.addEventListener('click', () => {
        utils.setLoading(true);
        comm.send('toggleGrabDriver');
    });

    DOM.unregisterDriverBtn.addEventListener('click', () => {
        utils.setLoading(true);
        comm.send('toggleGrabDriver');
    });

    DOM.acceptRideBtn.addEventListener('click', () => {
        if (state.pendingRequest?.rideId) {
            comm.send('acceptGrabRide', { rideId: state.pendingRequest.rideId });
            
            // Khi tài xế chấp nhận, hiển thị điểm đón khách và điểm đến
            if (state.pendingRequest.pickupCoords) {
                state.pickup = state.pendingRequest.pickupCoords;
                markerFn.create('pickup', state.pickup.x, state.pickup.y, '📍 Điểm đón khách');
            }
            if (state.pendingRequest.dropoffCoords) {
                state.dropoff = state.pendingRequest.dropoffCoords;
                markerFn.create('dropoff', state.dropoff.x, state.dropoff.y, '🏁 Điểm đến');
            }
            
            state.pendingRequest = null;
            state.hasRide = true;
            state.rideStatus = 'picking_up';
            ui.update();
            utils.showStatus('Đã chấp nhận chuyến xe! Tự động đến điểm đón.', 'success');
        }
    });

    DOM.rejectRideBtn.addEventListener('click', () => {
        if (state.pendingRequest?.rideId) {
            comm.send('rejectGrabRide', { rideId: state.pendingRequest.rideId });
            state.pendingRequest = null;
            state.rideData = null;
            ui.update();
            utils.showStatus('Đã từ chối chuyến xe', 'info');
        }
    });

    DOM.cancelDriverRideBtn.addEventListener('click', () => {
        const rideId = state.rideData?.rideId || state.pendingRequest?.rideId;
        if (rideId) {
            comm.send(state.rideData ? 'cancelGrabRide' : 'rejectGrabRide', { rideId });
        }
        state.hasRide = false;
        state.pendingRequest = null;
        state.rideData = null;
        state.rideStatus = null;
        ui.update();
        markerFn.cleanup(); // Chỉ xóa khi hủy chuyến
        utils.showStatus('Đã hủy chuyến xe!');
    });

    window.addEventListener('message', comm.handleMsg);
};

// Hàm để bắt đầu tracking coordinates từ UI
const startCoordinateTracking = () => {
    comm.send('toggleUpdateCoords', { toggle: true });
};
document.addEventListener('DOMContentLoaded', () => {
    // Check if DOM elements exist
    console.log('DOM elements check:');
    console.log('passengerBtn:', DOM.passengerBtn);
    console.log('driverBtn:', DOM.driverBtn);
    console.log('passengerPanel:', DOM.passengerPanel);
    console.log('driverPanel:', DOM.driverPanel);
    console.log('mainMenu:', DOM.mainMenu);
    
    // Start with main menu
    utils.showMainMenu();
    setupEvents();

    if (mapFn.init()) {
        setTimeout(() => {
            comm.send('getCurrentLocation');
            comm.send('getGrabDriverStatus');
            comm.send('toggleUpdateCoords', { toggle: true });
            
            // Bắt đầu cập nhật vị trí ngay lập tức
            startCoordinateTracking();
        }, 300);

        // Tự động cập nhật vị trí mỗi 2 giây
        setInterval(() => {
            comm.send('getCurrentLocation');
        }, 2000);

        // Tự động cập nhật danh sách tài xế mỗi 5 giây
        setInterval(() => {
            if (!state.hasRide) {
                comm.send('getAllGrabDrivers');
            }
        }, 5000);
    }

    utils.showStatus('Ứng dụng Grab đã sẵn sàng!');
});

window.addEventListener('beforeunload', () => comm.send('toggleUpdateCoords', { toggle: false }));