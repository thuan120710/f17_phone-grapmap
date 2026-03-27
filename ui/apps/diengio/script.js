let isRented = true; // Giả lập trạng thái đã thuê trạm
let isExpired = false; // Giả lập trạng thái đã hết hạn

function initApp() {
    if (isExpired) {
        document.getElementById('welcome-view').classList.add('hidden');
        document.getElementById('owned-view').classList.add('hidden');
        document.getElementById('expired-view').classList.remove('hidden');
    } else if (isRented) {
        document.getElementById('welcome-view').classList.add('hidden');
        document.getElementById('owned-view').classList.remove('hidden');
        document.getElementById('expired-view').classList.add('hidden');
    } else {
        document.getElementById('welcome-view').classList.remove('hidden');
        document.getElementById('owned-view').classList.add('hidden');
        document.getElementById('expired-view').classList.add('hidden');
    }
}

function showWelcomeView() {
    document.getElementById('main-view').classList.add('hidden');
    initApp(); // Sử dụng initApp để quay lại đúng trạng thái hiện tại
}

function showMainView() {
    document.getElementById('welcome-view').classList.add('hidden');
    document.getElementById('owned-view').classList.add('hidden');
    document.getElementById('expired-view').classList.add('hidden');
    document.getElementById('main-view').classList.remove('hidden');
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
    // Cập nhật text trên thanh filter chính
    document.getElementById('selectedFilterText').innerText = filterName;

    // Cập nhật trạng thái active cho các option và radio buttons
    const options = document.querySelectorAll('.option-item');
    options.forEach(opt => {
        opt.classList.remove('active');
        opt.querySelector('.radio-btn').classList.remove('active');
    });

    element.classList.add('active');
    element.querySelector('.radio-btn').classList.add('active');

    // Đóng menu sau khi chọn
    setTimeout(() => toggleMenu(false), 200);

    // Logic lọc danh sách trạm có thể thêm ở đây
    console.log('Selected filter:', filterName);
}

function setWaypoint(stationId) {
    const stations = {
        1: { x: 50.0, y: 50.0, name: "Trạm Điện Gió 1" },
        2: { x: 150.0, y: 150.0, name: "Trạm Điện Gió 2" },
        3: { x: 100.0, y: 100.0, name: "Trạm Điện Gió 3" },
        4: { x: 200.0, y: 200.0, name: "Trạm Điện Gió 4" },
        5: { x: 300.0, y: 300.0, name: "Trạm Điện Gió 5" },
        6: { x: 400.0, y: 400.0, name: "Trạm Điện Gió 6" }
    };


    const station = stations[stationId];
    if (station) {
        // Gửi dữ liệu về game (FiveM) để đặt waypoint
        // LB Phone thường sử dụng NUI Callback
        fetch(`https://${JSON.stringify(window.nuiHandshake || 'f17_phone')}/setWaypoint`, {
            method: 'POST',
            body: JSON.stringify({
                x: station.x,
                y: station.y,
                label: station.name
            })
        }).then(resp => resp.json()).then(data => {
            console.log('Waypoint set:', data);
            // Có thể thêm thông báo trong UI ở đây
        }).catch(err => {
            console.error('Lỗi khi đặt waypoint:', err);
            // Fallback cho môi trường browser test
            alert(`Đã đặt vị trí tới ${station.name}`);
        });
    }
}

// Log khi load app
console.log("Diengio App Loaded with Welcome/Owned View Logic");
initApp();
