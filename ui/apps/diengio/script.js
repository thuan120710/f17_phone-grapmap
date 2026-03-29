let currentAppData = null;
let refreshInterval = null;
let currentFilter = 'TẤT CẢ';
function initApp() {
    fetchAppData();

    // Refresh mỗi 10 giây để lấy dữ liệu mới từ Server
    if (refreshInterval) clearInterval(refreshInterval);
    refreshInterval = setInterval(fetchAppData, 10000);
}

async function fetchAppData() {
    try {
        const resourceName = window.nuiHandshake || 'lb-phone';
        const response = await fetch(`https://${resourceName}/DiengioApp`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json; charset=UTF-8'
            },
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

    // Nếu đang ở màn hình Danh sách tất cả trạm thì không tự động chuyển view
    // Chỉ cập nhật danh sách ở bên dưới
    const isMainViewOpen = !document.getElementById('main-view').classList.contains('hidden');

    if (!isMainViewOpen) {
        if (data.owned) {
            const details = data.details;
            if (details.isExpired) {
                showView('expired-view');
                renderExpiredView(data.turbineId, details);
            } else {
                showView('owned-view');
                renderOwnedView(data.turbineId, details);
            }
        } else {
            showView('welcome-view');
        }
    } else {
        // Vẫn cập nhật dữ liệu ngầm cho các view khác nhỡ User bấm back
        if (data.owned) {
            const details = data.details;
            if (details.isExpired) renderExpiredView(data.turbineId, details);
            else renderOwnedView(data.turbineId, details);
        }
    }

    applyFilterAndRender();
}

function applyFilterAndRender() {
    if (!currentAppData || !currentAppData.allStations) return;

    let filteredStations = currentAppData.allStations;
    if (currentFilter === 'TRẠM CÒN TRỐNG') {
        filteredStations = currentAppData.allStations.filter(s => !s.isRented && !s.isExpired);
    }

    renderStationList(filteredStations);
}

function showView(viewId) {
    const views = ['welcome-view', 'owned-view', 'expired-view', 'main-view'];
    views.forEach(id => {
        const el = document.getElementById(id);
        if (el) {
            if (id === viewId) el.classList.remove('hidden');
            else el.classList.add('hidden');
        }
    });
}

function renderOwnedView(id, details) {
    document.querySelector('#owned-view .owned-id').innerText = `TRẠM ${id}`;

    // Tính toán thời gian còn lại
    if (details.expiryTime) {
        const remainingStr = formatRemainingTime(details.expiryTime);
        document.querySelector('#owned-view .owned-timer').innerText = `Còn ${remainingStr}`;
    }

    // Trạng thái hệ thống
    const statusText = details.onDuty ?
        `<span class="dot-online"></span> ONLINE - ${(details.workHours || 0).toFixed(1)} / 12 GIỜ` :
        `<span class="dot-offline"></span> OFFLINE - ${(details.workHours || 0).toFixed(1)} / 12 GIỜ`;
    document.querySelector('#owned-view .system-value').innerHTML = statusText;

    // Hiệu suất & Thu nhập
    const efficiency = Math.floor(details.efficiency || 0);
    document.querySelector('#owned-view .percentage').innerText = `${efficiency}%`;
    document.querySelector('#owned-view .circular-progress').style.background =
        `conic-gradient(#00ff66 ${efficiency}%, #333 0)`;

    document.querySelector('#owned-view .income-value-owned').innerText = formatMoney(details.earnings || 0);

    // Chi tiết hệ thống
    const systems = details.systems || {};
    const systemRows = document.querySelectorAll('#owned-view .status-row');

    const sysMap = [
        { key: 'lubrication', name: 'ỔN ĐỊNH' },
        { key: 'electric', name: 'ĐIỆN ÁP' },
        { key: 'blades', name: 'KẾT CẤU' },
        { key: 'stability', name: 'TRỤC XOAY' },
        { key: 'safety', name: 'AN TOÀN' }
    ];

    sysMap.forEach((sys, index) => {
        if (systemRows[index]) {
            const val = Math.floor(systems[sys.key] || 0);
            const row = systemRows[index];
            row.querySelector('.status-percent').innerText = `${val}%`;
            row.querySelector('.progress-bar').style.width = `${val}%`;

            // Đổi màu dựa trên giá trị
            row.classList.remove('green', 'yellow', 'red');
            if (val > 50) row.classList.add('green');
            else if (val > 30) row.classList.add('yellow');
            else row.classList.add('red');
        }
    });

    // Cập nhật GPS button trong header
    const gpsBtn = document.querySelector('#owned-view .gps-btn');
    gpsBtn.onclick = () => setWaypoint(id);
}

function renderExpiredView(id, details) {
    document.querySelector('#expired-view .owned-id').innerText = `TRẠM ${id}`;
    document.querySelector('#expired-view .expired-amount').innerText = `${formatMoney(details.earnings || 0)} IC`;

    if (details.withdrawDeadline) {
        const remainingStr = formatRemainingTime(details.withdrawDeadline);
        document.querySelector('#expired-view .expired-sub-timer').innerText = remainingStr;
    }

    const gpsBtn = document.querySelector('#expired-view .gps-btn');
    gpsBtn.onclick = () => setWaypoint(id);
}

function renderStationList(stations) {
    const listContainer = document.getElementById('stationList');
    if (!listContainer || !stations) return;

    let availableCount = 0;
    let html = '';

    stations.forEach(station => {
        const isAvailable = !station.isRented && !station.isExpired;
        if (isAvailable) availableCount++;

        let statusClass = isAvailable ? 'available' : (station.isExpired ? 'expired' : 'active');
        let statusText = isAvailable ? 'Có thể thuê' : (station.isExpired ? 'Hết hạn' : 'Đã thuê');

        // Format thời gian hiển thị (Hh Mp) - Đồng bộ 100% với Owned View
        if (station.expiryTime) {
            statusText = `Còn ${formatRemainingTime(station.expiryTime)}`;
        } else if (station.timespan && station.timespan !== "00:00:00") {
            const parts = station.timespan.split(':');
            if (parts.length === 3) {
                // Parse chuỗi HH:MM:SS từ server thành giây để dùng hàm format cho đồng nhất
                const totalSeconds = parseInt(parts[0]) * 3600 + parseInt(parts[1]) * 60 + parseInt(parts[2]);
                const fakeExpiry = Math.floor(Date.now() / 1000) + totalSeconds;
                statusText = `Còn ${formatRemainingTime(fakeExpiry)}`;
            } else {
                statusText = `Còn ${station.timespan}`;
            }
        }

        html += `
            <div class="station-item">
                <div class="station-status-dot ${statusClass}"></div>
                <div class="station-name">TRẠM ${station.id}</div>
                <div class="station-status-text ${statusClass}">${statusText}</div>
                <button class="gps-btn" onclick="setWaypoint(${station.id})">
                    <span class="gps-icon"></span> GPS
                </button>
            </div>
        `;
    });

    listContainer.innerHTML = html;

    // Cập nhật số trạm còn trống động (Toàn thế giới)
    const summaryElem = document.querySelector('.status-summary');
    if (summaryElem && currentAppData && currentAppData.allStations) {
        const totalAvailable = currentAppData.allStations.filter(s => !s.isRented && !s.isExpired).length;
        summaryElem.innerHTML = `Số trạm còn trống: <span class="highlight">${totalAvailable}</span> / ${currentAppData.allStations.length}`;
    }
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
    // Ẩn main-view trước để updateUI có thể thực hiện chuyển đổi view
    document.getElementById('main-view').classList.add('hidden');
    updateUI(currentAppData);
}

function showMainView() {
    showView('main-view');
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
    document.getElementById('selectedFilterText').innerText = filterName;

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
        headers: {
            'Content-Type': 'application/json; charset=UTF-8'
        },
        body: JSON.stringify({
            action: 'setWaypoint',
            id: stationId
        })
    });
}

// Khi đóng app, dọn dẹp interval
window.addEventListener('message', function (event) {
    if (event.data.action === 'closeApp') {
        if (refreshInterval) clearInterval(refreshInterval);
    }
});

// Debug: Phím tắt cho môi trường Dev (F2 để xem màn hình hết hạn)
// window.addEventListener('keydown', function (event) {
//     if (event.code === 'F2') {
//         const dummyData = {
//             owned: true,
//             turbineId: 99,
//             details: {
//                 isExpired: true,
//                 earnings: 125000,
//                 withdrawDeadline: Math.floor(Date.now() / 1000) + 7200 // Còn 2 tiếng
//             },
//             allStations: currentAppData ? currentAppData.allStations : []
//         };
//         console.log("Dev Mode: Kích hoạt Expired View");
//         updateUI(dummyData);
//     }

//     // F3 để quay lại trạng thái thực tế từ server
//     if (event.code === 'F3') {
//         console.log("Dev Mode: Quay lại dữ liệu thực tế");
//         fetchAppData();
//     }
// });

// console.log("Diengio App Loaded with Dynamic Data Logic (Dev Mode: F2-Expired, F3-Real)");
initApp();
