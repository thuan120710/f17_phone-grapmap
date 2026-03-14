# Cập Nhật UI Grab - Tóm Tắt

## 🎨 Các Thay Đổi UI

### 1. Cập Nhật State Management

**Thêm các biến state mới:**
```javascript
let pickupLocation = null;          // Điểm đón
let dropoffLocation = null;         // Điểm trả
let driverMarker = null;            // Marker tài xế (tracking)
let pickupMarker = null;            // Marker điểm đón
let dropoffMarker = null;           // Marker điểm trả
let rideStatus = null;              // waiting, picking_up, in_progress, completed, cancelled
```

---

### 2. Hàm Quản Lý Markers

#### `updateDriverMarker(x, y, vehiclePlate)`
- Cập nhật vị trí tài xế realtime
- Hiển thị biển số xe trong popup
- Marker màu xanh dương

#### `createPickupMarker(x, y)`
- Tạo marker điểm đón
- Marker màu xanh lá
- Icon: 📍 Điểm đón

#### `createDropoffMarker(x, y)`
- Tạo marker điểm trả
- Marker màu cam
- Icon: 🏁 Điểm trả

#### `cleanupRideMarkers()`
- Xóa tất cả markers liên quan đến chuyến đi
- Gọi khi hoàn thành hoặc hủy chuyến

---

### 3. Luồng Đặt Xe Mới

**Trước:**
```javascript
requestRideBtn.click() → sendMessage('requestGrabRide')
```

**Sau:**
```javascript
requestRideBtn.click() 
  → Hiển thị thông báo "Nhấn vào bản đồ để chọn điểm trả"
  → map.on('click', selectDropoff)
  → Người dùng click vào bản đồ
  → Tạo dropoffMarker tại vị trí click
  → sendMessage('requestGrabRide', {
      pickupCoords: currentLocation,
      dropoffCoords: dropoffLocation
    })
```

**Lợi ích:**
- Người dùng chọn điểm trả trực quan trên bản đồ
- Hiển thị marker điểm trả ngay lập tức
- Gửi cả 2 tọa độ (pickup + dropoff) cho server

---

### 4. Xử Lý Events Mới

#### `grab:newRideRequest`
```javascript
// Cho tài xế - hiển thị yêu cầu mới
{
    rideId, passengerName, passengerId,
    pickupDistance, tripDistance, price
}
```

#### `grab:rideAccepted`
```javascript
// Cho khách - tài xế đã chấp nhận
{
    rideId, status, vehiclePlate, 
    driverName, driverId, driverCoords
}
// → Tạo driverMarker để tracking
```

#### `grab:driverLocationUpdate`
```javascript
// Cập nhật vị trí tài xế mỗi 3 giây
{
    x, y, vehiclePlate, status
}
// → updateDriverMarker(x, y, vehiclePlate)
```

#### `grab:updateRideStatus`
```javascript
// Cập nhật trạng thái chuyến đi
{
    rideId, status, message, vehiclePlate, price
}
// → Cập nhật UI theo status
```

#### `grab:showDropoffLocation`
```javascript
// Hiển thị điểm trả cho khách khi tài xế đến đón
{
    rideId, x, y
}
// → createDropoffMarker(x, y)
```

#### `grab:updateDistance`
```javascript
// Cập nhật khoảng cách cho tài xế
{
    distance, type: "pickup" | "dropoff"
}
// → Hiển thị "Còn Xm đến điểm đón/trả"
```

#### `grab:updateDropoffDistance`
```javascript
// Cập nhật khoảng cách đến điểm trả cho khách
{
    distance
}
// → Hiển thị "Còn Xm đến điểm trả"
```

#### `grab:arrivedAtDropoff`
```javascript
// Tài xế đã đến điểm trả
// → Hiển thị nút "Hoàn thành"
```

---

### 5. Hiển Thị Thông Tin Chi Tiết

**Trước:**
```javascript
rideDetails.textContent = `Khoảng cách: ${data.distance}m`;
```

**Sau:**
```javascript
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
}
rideDetails.textContent = detailsText;
```

**Hiển thị:**
```
Mã: GRAB20260313120530123
Tài xế: Nguyen Van A
Biển số: ABC123
Quãng đường: 1.5km
```

---

### 6. Cập Nhật Trạng Thái Theo Status

| Status | Tài xế | Khách | Nút hiển thị |
|--------|--------|-------|--------------|
| `waiting` | ⏳ Có yêu cầu chuyến xe | ⏳ Đang chờ tài xế chấp nhận | Accept/Reject |
| `picking_up` | 🚗 Đang đến đón khách | 🚗 Tài xế đang đến đón | Arrived |
| `in_progress` | 🚕 Đang chở khách | 🚕 Đang trên đường | Complete |
| `completed` | ✅ Hoàn thành | ✅ Hoàn thành | - |
| `cancelled` | ❌ Đã hủy | ❌ Đã hủy | - |

---

### 7. Cải Thiện CSS

#### Status Bar với màu sắc
```css
.status-bar.info {
    background: #d1ecf1;
    border-color: #bee5eb;
    color: #0c5460;
}

.status-bar.success {
    background: #d4edda;
    border-color: #c3e6cb;
    color: #155724;
}

.status-bar.error {
    background: #f8d7da;
    border-color: #f5c6cb;
    color: #721c24;
}
```

#### Info Value với word-wrap
```css
.info-value {
    color: #333;
    font-weight: 500;
    font-size: 14px;
    text-align: right;
    max-width: 60%;
    word-wrap: break-word;
}
```

---

### 8. Cleanup Logic

**Khi hoàn thành/hủy chuyến:**
```javascript
cleanupRideMarkers();  // Xóa tất cả markers
hasActiveRide = false;
currentRideData = null;
rideStatus = null;
pendingRideRequest = null;
```

**Khi quay lại main menu:**
```javascript
clearDriverMarkers();   // Xóa markers tài xế online
cleanupRideMarkers();   // Xóa markers chuyến đi
```

---

### 9. Tracking Realtime

**Luồng tracking tài xế:**
```
1. Khách đặt xe
2. Tài xế chấp nhận → grab:rideAccepted
3. Tạo driverMarker tại vị trí tài xế
4. Mỗi 3 giây: grab:driverLocationUpdate
5. updateDriverMarker(newX, newY)
6. Marker di chuyển mượt mà trên bản đồ
7. Tài xế đến → grab:driverArrived
8. Xóa driverMarker
9. Tạo dropoffMarker
```

---

### 10. Các Nút Điều Khiển

#### Cho Khách Hàng:
- **Đặt xe Grab**: Chuyển sang chế độ chọn điểm trả
- **Đặt xe ngay**: Click vào bản đồ để chọn điểm trả
- **Hủy chuyến**: Hủy chuyến đang chờ/đang diễn ra

#### Cho Tài Xế:
- **Chấp nhận chuyến**: Nhận chuyến xe mới
- **Từ chối**: Từ chối chuyến xe
- **Đã đến điểm đón**: Xác nhận đã đón khách
- **Hoàn thành chuyến**: Kết thúc chuyến đi

---

## 🎯 Tính Năng Nổi Bật

✅ **Chọn điểm trả trực quan**: Click vào bản đồ
✅ **Tracking realtime**: Cập nhật vị trí tài xế mỗi 3s
✅ **Hiển thị đầy đủ thông tin**: Mã chuyến, tên, biển số
✅ **Markers màu sắc**: Xanh lá (đón), Cam (trả), Xanh dương (tài xế)
✅ **Status bar động**: Màu sắc theo loại thông báo
✅ **Cleanup tự động**: Xóa markers khi hoàn thành
✅ **Responsive**: Hiển thị tốt trên mọi kích thước màn hình

---

## 🔄 Luồng Hoàn Chỉnh

### Khách Hàng:
```
1. Mở app → Hiển thị vị trí hiện tại
2. Nhấn "Đặt xe Grab"
3. Nhấn "Đặt xe ngay"
4. Click vào bản đồ chọn điểm trả
5. Marker cam xuất hiện tại điểm trả
6. Đợi tài xế chấp nhận
7. Marker xanh dương (tài xế) xuất hiện
8. Theo dõi tài xế di chuyển đến
9. Tài xế đến → Marker tài xế biến mất
10. Marker cam (điểm trả) xuất hiện
11. Theo dõi khoảng cách đến điểm trả
12. Hoàn thành → Hiển thị giá tiền
```

### Tài Xế:
```
1. Mở app → Bật "Đăng ký làm tài xế"
2. Marker chuyển sang màu xanh lá
3. Nhận thông báo yêu cầu mới
4. Nhấn "Chấp nhận chuyến"
5. Marker xanh lá (điểm đón) xuất hiện
6. Đi đến điểm đón
7. Cập nhật khoảng cách realtime
8. Đến gần (< 15m) → Nhấn "Đã đến điểm đón"
9. Marker chuyển sang cam (điểm trả)
10. Đi đến điểm trả
11. Đến gần (< 15m) → Nhấn "Hoàn thành"
12. Nhận tiền → Hiển thị thông báo
```

---

## 📝 Ghi Chú Kỹ Thuật

- **Tọa độ**: Sử dụng `[y, x]` cho Leaflet (Lat = Y, Lng = X)
- **Marker colors**: 
  - Xanh lá: Tài xế online / Điểm đón
  - Xanh dương: Tài xế đang phục vụ
  - Cam: Điểm trả
  - Đỏ: Tài xế bận
- **Update frequency**: 3 giây cho vị trí tài xế
- **Auto-detect**: 15 mét để phát hiện đến nơi
- **Cleanup**: Tự động xóa markers khi hoàn thành/hủy

---

## ✅ Checklist UI

- [x] Chọn điểm trả bằng click vào bản đồ
- [x] Hiển thị marker điểm đón (xanh lá)
- [x] Hiển thị marker điểm trả (cam)
- [x] Tracking tài xế realtime (xanh dương)
- [x] Hiển thị mã chuyến
- [x] Hiển thị tên tài xế
- [x] Hiển thị biển số xe
- [x] Hiển thị tên khách (cho tài xế)
- [x] Hiển thị quãng đường
- [x] Hiển thị giá tiền
- [x] Status bar với màu sắc
- [x] Cập nhật trạng thái theo status
- [x] Cleanup markers tự động
- [x] Responsive design

---

## 🚀 Kết Luận

UI đã được cập nhật hoàn chỉnh để phù hợp với logic backend mới:
- Hỗ trợ chọn điểm đón và điểm trả
- Tracking realtime với markers
- Hiển thị đầy đủ thông tin chuyến đi
- Trạng thái rõ ràng theo từng giai đoạn
- Cleanup tự động và UX mượt mà
