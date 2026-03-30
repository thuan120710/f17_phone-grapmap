let currentAppData = null;
let refreshInterval = null;
let currentFilter = 'TẤT CẢ';

// UI Elements Cache
const elements = {
    views: {
        welcome: null,
        owned: null,
        expired: null,
        main: null
    },
    owned: {
        stationId: null,
        expiryTimer: null,
        systemStatus: null,
        efficiencyCircle: null,
        efficiencyValue: null,
        earningsValue: null,
        statusList: null,
        gpsBtn: null
    },
    expired: {
        stationId: null,
        timer: null,
        systemStatus: null,
        totalEarnings: null,
        withdrawTimer: null,
        gpsBtn: null
    },
    main: {
        list: null,
        availableCount: null,
        totalCount: null,
        filterText: null,
        template: null
    }
};

function initApp() {
    cacheElements();
    fetchAppData();

    if (refreshInterval) clearInterval(refreshInterval);
    refreshInterval = setInterval(fetchAppData, 10000);
}

function cacheElements() {
    // Views
    elements.views.welcome = document.getElementById('welcome-view');
    elements.views.owned = document.getElementById('owned-view');
    elements.views.expired = document.getElementById('expired-view');
    elements.views.main = document.getElementById('main-view');

    // Owned View
    elements.owned.stationId = document.getElementById('owned-station-id');
    elements.owned.expiryTimer = document.getElementById('owned-expiry-timer');
    elements.owned.systemStatus = document.getElementById('owned-system-status');
    elements.owned.efficiencyCircle = document.getElementById('efficiency-circle');
    elements.owned.efficiencyValue = document.getElementById('efficiency-value');
    elements.owned.earningsValue = document.getElementById('total-earnings-value');
    elements.owned.statusList = document.getElementById('system-status-list');
    elements.owned.gpsBtn = document.getElementById('owned-gps-btn');

    // Expired View
    elements.expired.stationId = document.getElementById('expired-station-id');
    elements.expired.timer = document.getElementById('expired-timer');
    elements.expired.systemStatus = document.getElementById('expired-system-status');
    elements.expired.totalEarnings = document.getElementById('expired-total-earnings');
    elements.expired.withdrawTimer = document.getElementById('expired-withdraw-timer');
    elements.expired.gpsBtn = document.getElementById('expired-gps-btn');

    // Main View
    elements.main.list = document.getElementById('stationList');
    elements.main.availableCount = document.getElementById('available-count');
    elements.main.totalCount = document.getElementById('total-count');
    elements.main.filterText = document.getElementById('selectedFilterText');
    elements.main.template = document.getElementById('station-item-template');
}

async function fetchAppData() {
    try {
        const resourceName = window.nuiHandshake || 'lb-phone';
        const response = await fetch(`https://${resourceName}/DiengioApp`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify({ action: 'getAppData' })
        });
        const data = await response.json();
        currentAppData = data;
        updateUI(data);
    } catch (err) {
        console.error('Lỗi khi tải dữ liệu Điện Gió:', err);
    }
}

function updateUI(data) {
    if (!data) return;

    const isMainViewOpen = !elements.views.main.classList.contains('hidden');

    if (!isMainViewOpen) {
        if (data.owned && data.details) {
            const details = data.details;
            if (details.isExpired) {
                showView('expired');
                renderExpiredView(data.turbineId, details);
            } else {
                showView('owned');
                renderOwnedView(data.turbineId, details);
            }
        } else {
            showView('welcome');
        }
    } else if (data.owned && data.details) {
        const details = data.details;
        if (details.isExpired) renderExpiredView(data.turbineId, details);
        else renderOwnedView(data.turbineId, details);
    }

    applyFilterAndRender();
}

function showView(viewName) {
    Object.keys(elements.views).forEach(name => {
        const el = elements.views[name];
        if (el) {
            if (name === viewName) el.classList.remove('hidden');
            else el.classList.add('hidden');
        }
    });
}

function renderOwnedView(id, details) {
    elements.owned.stationId.innerText = `TRẠM ${id}`;

    if (details.expiryTime) {
        elements.owned.expiryTimer.innerText = `Còn ${formatRemainingTime(details.expiryTime)}`;
    }

    // Trạng thái hệ thống
    const statusText = details.onDuty ?
        `<span class="dot-online"></span> ONLINE - ${(details.workHours || 0).toFixed(1)} / 12 GIỜ` :
        `<span class="dot-offline"></span> OFFLINE - ${(details.workHours || 0).toFixed(1)} / 12 GIỜ`;
    elements.owned.systemStatus.innerHTML = statusText;

    // Hiệu suất & Thu nhập
    const efficiency = Math.floor(details.efficiency || 0);
    elements.owned.efficiencyValue.innerText = `${efficiency}%`;
    elements.owned.efficiencyCircle.style.background = `conic-gradient(#00ff66 ${efficiency}%, #333 0)`;
    elements.owned.earningsValue.innerText = formatMoney(details.earnings || 0);

    // Chi tiết hệ thống
    const systems = details.systems || {};
    const rows = elements.owned.statusList.querySelectorAll('.status-row');

    rows.forEach(row => {
        const sysKey = row.getAttribute('data-sys');
        if (sysKey && systems[sysKey] !== undefined) {
            const val = Math.floor(systems[sysKey]);
            row.querySelector('.status-percent').innerText = `${val}%`;
            row.querySelector('.progress-bar').style.width = `${val}%`;

            row.classList.remove('green', 'yellow', 'red');
            if (val > 50) row.classList.add('green');
            else if (val > 30) row.classList.add('yellow');
            else row.classList.add('red');
        }
    });

    elements.owned.gpsBtn.onclick = () => setWaypoint(id);
}

function renderExpiredView(id, details) {
    elements.expired.stationId.innerText = `TRẠM ${id}`;
    elements.expired.totalEarnings.innerText = `${formatMoney(details.earnings || 0)} IC`;

    if (details.withdrawDeadline) {
        elements.expired.withdrawTimer.innerText = formatRemainingTime(details.withdrawDeadline);
    }

    elements.expired.gpsBtn.onclick = () => setWaypoint(id);
}

function renderStationList(stations) {
    if (!elements.main.list || !stations) return;

    elements.main.list.innerHTML = '';
    const fragment = document.createDocumentFragment();

    stations.forEach(station => {
        const isAvailable = !station.isRented && !station.isExpired;
        const statusClass = isAvailable ? 'available' : (station.isExpired ? 'expired' : 'active');
        let statusText = isAvailable ? 'Có thể thuê' : (station.isExpired ? 'Hết hạn' : 'Đã thuê');

        if (station.expiryTime) {
            statusText = `Còn ${formatRemainingTime(station.expiryTime)}`;
        } else if (station.timespan && station.timespan !== "00:00:00") {
            const parts = station.timespan.split(':');
            if (parts.length === 3) {
                const totalSeconds = parseInt(parts[0]) * 3600 + parseInt(parts[1]) * 60 + parseInt(parts[2]);
                const fakeExpiry = Math.floor(Date.now() / 1000) + totalSeconds;
                statusText = `Còn ${formatRemainingTime(fakeExpiry)}`;
            }
        }

        const clone = elements.main.template.content.cloneNode(true);
        const item = clone.querySelector('.station-item');

        const dot = item.querySelector('.station-status-dot');
        dot.className = `station-status-dot ${statusClass}`;

        item.querySelector('.station-name').innerText = `TRẠM ${station.id}`;

        const text = item.querySelector('.station-status-text');
        text.className = `station-status-text ${statusClass}`;
        text.innerText = statusText;

        const btn = item.querySelector('.gps-btn');
        btn.onclick = () => setWaypoint(station.id);

        fragment.appendChild(clone);
    });

    elements.main.list.appendChild(fragment);

    // Cập nhật số trạm còn trống
    if (currentAppData && currentAppData.allStations) {
        const totalAvailable = currentAppData.allStations.filter(s => !s.isRented && !s.isExpired).length;
        elements.main.availableCount.innerText = totalAvailable;
        elements.main.totalCount.innerText = currentAppData.allStations.length;
    }
}

function applyFilterAndRender() {
    if (!currentAppData || !currentAppData.allStations) return;

    let filteredStations = currentAppData.allStations;
    if (currentFilter === 'TRẠM CÒN TRỐNG') {
        filteredStations = currentAppData.allStations.filter(s => !s.isRented && !s.isExpired);
    }

    renderStationList(filteredStations);
}

function formatRemainingTime(timestamp) {
    const now = Math.floor(Date.now() / 1000);
    const diff = Math.max(0, timestamp - now);
    const h = Math.floor(diff / 3600);
    const m = Math.floor((diff % 3600) / 60);
    return `${h}h ${m}p`;
}

function formatMoney(n) {
    return n.toLocaleString('en-US');
}

function showWelcomeView() {
    elements.views.main.classList.add('hidden');
    updateUI(currentAppData);
}

function showMainView() {
    showView('main');
}

function toggleMenu(show) {
    const menu = document.getElementById('bottomMenu');
    const overlay = document.getElementById('menuOverlay');

    if (show) {
        overlay.style.display = 'block';
        setTimeout(() => menu.classList.add('active'), 10);
    } else {
        menu.classList.remove('active');
        setTimeout(() => overlay.style.display = 'none', 300);
    }
}

function selectOption(filterName, element) {
    currentFilter = filterName;
    elements.main.filterText.innerText = filterName;

    const options = document.querySelectorAll('.option-item');
    options.forEach(opt => {
        opt.classList.remove('active');
        const radio = opt.querySelector('.radio-btn');
        if (radio) radio.classList.remove('active');
    });

    element.classList.add('active');
    const activeRadio = element.querySelector('.radio-btn');
    if (activeRadio) activeRadio.classList.add('active');

    applyFilterAndRender();
    setTimeout(() => toggleMenu(false), 200);
}

function setWaypoint(stationId) {
    const resourceName = window.nuiHandshake || 'lb-phone';
    fetch(`https://${resourceName}/DiengioApp`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify({ action: 'setWaypoint', id: stationId })
    });
}

window.addEventListener('message', function (event) {
    if (event.data.action === 'closeApp') {
        if (refreshInterval) clearInterval(refreshInterval);
    }
});
// Debug: Phím tắt cho môi trường Dev (F2 để xem màn hình hết hạn)
window.addEventListener('keydown', function (event) {
    if (event.code === 'F2') {
        const dummyData = {
            owned: true,
            turbineId: 99,
            details: {
                isExpired: true,
                earnings: 125000,
                withdrawDeadline: Math.floor(Date.now() / 1000) + 7200 // Còn 2 tiếng
            },
            allStations: currentAppData ? currentAppData.allStations : []
        };
        console.log("Dev Mode: Kích hoạt Expired View");
        updateUI(dummyData);
    }

    // F3 để quay lại trạng thái thực tế từ server
    if (event.code === 'F3') {
        console.log("Dev Mode: Quay lại dữ liệu thực tế");
        fetchAppData();
    }
});

console.log("Diengio App Loaded with Dynamic Data Logic (Dev Mode: F2-Expired, F3-Real)");

initApp();
