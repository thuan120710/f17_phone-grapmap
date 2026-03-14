# Hướng Dẫn Test Hệ Thống Grab

## 🧪 Chuẩn Bị Test

### Yêu cầu:
- 2 người chơi (1 khách, 1 tài xế)
- Hoặc 2 tab/cửa sổ game khác nhau
- Cả 2 đều có điện thoại và app Grab

---

## 📱 Test Case 1: Đăng Ký Tài Xế

### Bước thực hiện:
1. Người chơi A mở app Grab
2. Nhấn "Đăng ký làm tài xế"
3. Kiểm tra marker trên bản đồ chuyển sang màu xanh lá

### Kết quả mong đợi:
- ✅ Status badge: "Tài xế"
- ✅ Trạng thái: "🟢 Sẵn sàng nhận chuyến"
- ✅ Marker màu xanh lá trên bản đồ
- ✅ Hiển thị menu tài xế (Đang hoạt động, Hủy đăng ký)
- ✅ Thông báo: "Đã đăng ký làm tài xế!"

### Console log (Server):
```lua
activeDrivers[source] = {
    coords = {x, y, z},
    inVehicle = true/false,
    busy = false,
    vehiclePlate = "ABC123",
    driverId = "ABC12345",
    driverName = "Nguyen Van A"
}
```

---

## 📱 Test Case 2: Khách Đặt Xe

### Bước thực hiện:
1. Người chơi B mở app Grab
2. Nhấn "Đặt xe Grab"
3. Nhấn "Đặt xe ngay"
4. Click vào bản đồ để chọn điểm trả
5. Quan sát marker cam xuất hiện

### Kết quả mong đợi:
- ✅ Thông báo: "Nhấn vào bản đồ để chọn điểm trả"
- ✅ Click vào bản đồ → Marker cam xuất hiện
- ✅ Thông báo: "Đang tìm tài xế..."
- ✅ Sau vài giây: "Đã gửi yêu cầu! Mã chuyến: GRAB..."
- ✅ Trạng thái: "⏳ Đang chờ tài xế chấp nhận"

### Console log (Server):
```lua
activeRides[rideId] = {
    rideId = "GRAB20260313120530123",
    passenger = passengerSource,
    driver = driverSource,
    pickupCoords = {x, y, z},
    dropoffCoords = {x, y, z},
    pickupDistance = 250,
    tripDistance = 1500,
    price = 150,
    status = "waiting",
    ...
}
```

---

## 📱 Test Case 3: Tài Xế Nhận Yêu Cầu

### Bước thực hiện:
1. Tài xế (A) nhận thông báo trên màn hình
2. Kiểm tra thông tin: Tên khách, khoảng cách, giá
3. Nhấn Y hoặc nút "Chấp nhận chuyến"

### Kết quả mong đợi (Tài xế):
- ✅ Thông báo popup:
  ```
  [Grab] Yêu cầu đặt xe mới!
  Mã chuyến: GRAB20260313120530123
  Khách hàng: Tran Thi B
  Khoảng cách đón: 250m
  Quãng đường: 1.5km
  Thu nhập: $150
  ```
- ✅ Sau khi chấp nhận:
  - Marker xanh lá (điểm đón) xuất hiện
  - GPS route đến điểm đón
  - Trạng thái: "🚗 Đang đến đón khách"
  - Hiển thị thông tin khách trong "Chi tiết"

### Kết quả mong đợi (Khách):
- ✅ Thông báo: "Tài xế Nguyen Van A (ABC123) đã chấp nhận!"
- ✅ Marker xanh dương (tài xế) xuất hiện
- ✅ Trạng thái: "🚗 Tài xế đang đến đón"
- ✅ Hiển thị thông tin tài xế:
  ```
  Mã: GRAB20260313120530123
  Tài xế: Nguyen Van A
  Biển số: ABC123
  Quãng đường: 1.5km
  ```

### Console log (Server):
```lua
ride.status = "picking_up"
```

---

## 📱 Test Case 4: Tracking Realtime

### Bước thực hiện:
1. Tài xế di chuyển về phía điểm đón
2. Khách quan sát marker tài xế di chuyển

### Kết quả mong đợi:
- ✅ Marker xanh dương (tài xế) di chuyển mượt mà
- ✅ Cập nhật vị trí mỗi 3 giây
- ✅ Thông báo khoảng cách (cho tài xế): "Còn Xm đến điểm đón"

### Console log (Client):
```javascript
// Mỗi 3 giây
grab:driverLocationUpdate {
    x: 1234,
    y: 5678,
    vehiclePlate: "ABC123",
    status: "picking_up"
}
```

---

## 📱 Test Case 5: Tài Xế Đến Điểm Đón

### Bước thực hiện:
1. Tài xế đến gần điểm đón (< 15m)
2. Hệ thống tự động phát hiện hoặc nhấn "Đã đến điểm đón"

### Kết quả mong đợi (Tài xế):
- ✅ Thông báo: "Đã đón khách! Hãy đưa khách đến điểm trả."
- ✅ Marker xanh lá (điểm đón) biến mất
- ✅ Marker cam (điểm trả) xuất hiện
- ✅ GPS route chuyển sang điểm trả
- ✅ Trạng thái: "🚕 Đang chở khách"
- ✅ Nút "Hoàn thành chuyến" xuất hiện

### Kết quả mong đợi (Khách):
- ✅ Thông báo: "Tài xế đã đến! Chuyến đi bắt đầu."
- ✅ Marker xanh dương (tài xế) biến mất
- ✅ Marker cam (điểm trả) xuất hiện
- ✅ Trạng thái: "🚕 Đang trên đường"
- ✅ Thông báo khoảng cách: "Còn Xm đến điểm trả"

### Console log (Server):
```lua
ride.status = "in_progress"
ride.startTime = os.time()
```

---

## 📱 Test Case 6: Đến Điểm Trả

### Bước thực hiện:
1. Tài xế đến gần điểm trả (< 15m)
2. Hệ thống hiển thị thông báo
3. Tài xế nhấn "Hoàn thành chuyến"

### Kết quả mong đợi (Tài xế):
- ✅ Thông báo: "Đã đến điểm trả khách!"
- ✅ Sau khi nhấn "Hoàn thành":
  ```
  [Grab] Hoàn thành chuyến xe!
  Mã chuyến: GRAB20260313120530123
  Quãng đường: 1.5km
  + $150 Tiền mặt
  ```
- ✅ Nhận tiền vào tài khoản
- ✅ Trở về trạng thái "🟢 Sẵn sàng nhận chuyến"
- ✅ Tất cả markers biến mất

### Kết quả mong đợi (Khách):
- ✅ Thông báo:
  ```
  Hoàn thành!
  Mã: GRAB20260313120530123
  Quãng đường: 1.5km
  Chi phí: $150
  ```
- ✅ Trừ tiền từ tài khoản
- ✅ Trở về màn hình chính
- ✅ Tất cả markers biến mất

### Console log (Server):
```lua
ride.status = "completed"
Player.Functions.AddMoney("cash", 150, "grab-ride-payment")
PassengerPlayer.Functions.RemoveMoney("cash", 150, "grab-ride-charge")
activeRides[rideId] = nil
activeDrivers[driver].busy = false
```

---

## 📱 Test Case 7: Hủy Chuyến (Khách)

### Bước thực hiện:
1. Khách đặt xe
2. Trước khi tài xế đến, nhấn "Hủy chuyến"

### Kết quả mong đợi (Khách):
- ✅ Thông báo: "Đã hủy chuyến xe!"
- ✅ Trở về màn hình chính
- ✅ Tất cả markers biến mất

### Kết quả mong đợi (Tài xế):
- ✅ Thông báo: "Khách hàng đã hủy chuyến!"
- ✅ Marker điểm đón biến mất
- ✅ Trở về trạng thái "🟢 Sẵn sàng nhận chuyến"

### Console log (Server):
```lua
ride.status = "cancelled"
activeRides[rideId] = nil
activeDrivers[driver].busy = false
```

---

## 📱 Test Case 8: Hủy Chuyến (Tài Xế)

### Bước thực hiện:
1. Tài xế chấp nhận chuyến
2. Nhấn "Hủy chuyến"

### Kết quả mong đợi (Tài xế):
- ✅ Thông báo: "Đã hủy chuyến xe!"
- ✅ Trở về trạng thái "🟢 Sẵn sàng nhận chuyến"
- ✅ Tất cả markers biến mất

### Kết quả mong đợi (Khách):
- ✅ Thông báo: "Tài xế đã hủy chuyến!"
- ✅ Trở về màn hình chính
- ✅ Tất cả markers biến mất

---

## 📱 Test Case 9: Từ Chối Chuyến

### Bước thực hiện:
1. Tài xế nhận yêu cầu
2. Nhấn N hoặc "Từ chối"

### Kết quả mong đợi (Tài xế):
- ✅ Thông báo: "Đã từ chối chuyến xe!"
- ✅ Trở về trạng thái "🟢 Sẵn sàng nhận chuyến"

### Kết quả mong đợi (Khách):
- ✅ Thông báo: "Tài xế đã từ chối chuyến xe!"
- ✅ Trở về màn hình chính

---

## 📱 Test Case 10: Hủy Đăng Ký Tài Xế

### Bước thực hiện:
1. Tài xế đang hoạt động
2. Nhấn "Hủy đăng ký tài xế"

### Kết quả mong đợi:
- ✅ Thông báo: "Đã hủy đăng ký Grab!"
- ✅ Status badge: "Khách hàng"
- ✅ Marker chuyển sang màu xanh dương
- ✅ Trở về menu chính

### Nếu đang có chuyến:
- ✅ Chuyến đi bị hủy
- ✅ Khách nhận thông báo: "Tài xế đã hủy đăng ký!"

---

## 🔍 Kiểm Tra Chi Tiết

### Markers:
- [ ] Marker người chơi: Xanh dương (khách) / Xanh lá (tài xế)
- [ ] Marker tài xế tracking: Xanh dương
- [ ] Marker điểm đón: Xanh lá
- [ ] Marker điểm trả: Cam
- [ ] Marker tài xế online: Xanh lá (rảnh) / Đỏ (bận)

### Thông tin hiển thị:
- [ ] Mã chuyến: GRAB{timestamp}{playerID}
- [ ] Tên tài xế
- [ ] Biển số xe
- [ ] Tên khách (cho tài xế)
- [ ] Quãng đường (km)
- [ ] Giá tiền ($)
- [ ] Trạng thái rõ ràng

### GPS & Navigation:
- [ ] Route hiển thị đúng
- [ ] Blip màu sắc phù hợp
- [ ] Auto-detect đến nơi (< 15m)
- [ ] Chuyển GPS từ đón → trả tự động

### Realtime Updates:
- [ ] Vị trí tài xế cập nhật mỗi 3s
- [ ] Marker di chuyển mượt mà
- [ ] Khoảng cách cập nhật realtime
- [ ] UI cập nhật theo status

### Cleanup:
- [ ] Markers xóa khi hoàn thành
- [ ] Markers xóa khi hủy
- [ ] Data reset đúng
- [ ] Không còn blip thừa

---

## 🐛 Các Lỗi Thường Gặp

### 1. Marker không đổi màu
**Nguyên nhân:** Cache icon
**Giải pháp:** Thêm `?t=${Date.now()}` vào iconUrl

### 2. Không tìm thấy tài xế
**Nguyên nhân:** Tài xế không trong xe
**Giải pháp:** Đảm bảo tài xế ngồi trong xe

### 3. GPS không chuyển sang điểm trả
**Nguyên nhân:** Status không đúng
**Giải pháp:** Kiểm tra `ride.status = "in_progress"`

### 4. Marker không xóa
**Nguyên nhân:** Không gọi cleanup
**Giải pháp:** Gọi `cleanupRideMarkers()` khi hoàn thành/hủy

### 5. Không nhận được event
**Nguyên nhân:** Sai tên event hoặc không listen
**Giải pháp:** Kiểm tra tên event và `window.addEventListener('message')`

---

## ✅ Checklist Test Hoàn Chỉnh

### Khách hàng:
- [ ] Mở app thành công
- [ ] Hiển thị vị trí hiện tại
- [ ] Chọn điểm trả bằng click
- [ ] Đặt xe thành công
- [ ] Nhận thông báo tài xế chấp nhận
- [ ] Theo dõi tài xế di chuyển
- [ ] Nhận thông báo tài xế đến
- [ ] Theo dõi đến điểm trả
- [ ] Hoàn thành và trả tiền
- [ ] Hủy chuyến thành công

### Tài xế:
- [ ] Đăng ký tài xế thành công
- [ ] Marker chuyển màu xanh lá
- [ ] Nhận yêu cầu chuyến xe
- [ ] Chấp nhận chuyến thành công
- [ ] GPS hiển thị điểm đón
- [ ] Đến điểm đón tự động
- [ ] GPS chuyển sang điểm trả
- [ ] Hoàn thành và nhận tiền
- [ ] Hủy đăng ký thành công

### UI:
- [ ] Hiển thị đầy đủ thông tin
- [ ] Trạng thái cập nhật đúng
- [ ] Nút hiển thị phù hợp
- [ ] Màu sắc rõ ràng
- [ ] Responsive tốt

### Performance:
- [ ] Không lag khi tracking
- [ ] Markers render mượt
- [ ] Events xử lý nhanh
- [ ] Không memory leak

---

## 🎉 Kết Luận

Nếu tất cả test cases đều pass, hệ thống Grab đã hoạt động hoàn hảo!
