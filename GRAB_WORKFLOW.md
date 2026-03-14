# Hệ Thống Grab - Luồng Hoạt Động Chi Tiết

## 📋 Tổng Quan

Hệ thống Grab đã được cập nhật với đầy đủ tính năng chuyên nghiệp, bao gồm:
- ✅ Mã chuyến duy nhất (GRAB + timestamp + ID)
- ✅ Thông tin tài xế (ID, tên, biển số xe)
- ✅ Thông tin khách hàng (ID, tên)
- ✅ GPS điểm đón và điểm trả
- ✅ Cập nhật vị trí realtime
- ✅ UI hiển thị trạng thái chuyên nghiệp

---

## 🔄 Luồng Hoạt Động

### 1️⃣ Tài Xế Đăng Ký (Driver Registration)

**Client → Server:**
```lua
TriggerServerEvent("grab:toggleDriver", true)
```

**Server xử lý:**
- Lấy thông tin tài xế từ QBCore
- Lưu vào `activeDrivers`:
  - `coords`: Vị trí hiện tại
  - `inVehicle`: Có trong xe hay không
  - `busy`: Đang bận hay rảnh
  - `vehiclePlate`: Biển số xe
  - `driverId`: Citizen ID
  - `driverName`: Tên đầy đủ

**Server → Client:**
```lua
TriggerClientEvent("grab:driverStatus", src, true)
```

---

### 2️⃣ Khách Đặt Đơn (Passenger Request)

**Client gửi yêu cầu:**
```lua
AwaitCallback("grab:requestRide", pickupCoords, dropoffCoords)
```

**Dữ liệu gửi đi:**
- `pickupCoords`: Tọa độ điểm đón {x, y, z}
- `dropoffCoords`: Tọa độ điểm trả {x, y, z}

**Server xử lý:**
1. Tìm tài xế gần nhất (trong xe, không bận)
2. Tính khoảng cách:
   - `pickupDistance`: Khoảng cách từ tài xế → điểm đón
   - `tripDistance`: Khoảng cách từ điểm đón → điểm trả
3. Tính giá: `price = max(50, tripDistance * 0.1)`
4. Tạo mã chuyến: `GRAB{YYYYMMDDHHMMSS}{playerID}`

**Tạo ride object:**
```lua
activeRides[rideId] = {
    rideId = "GRAB20260313120530123",
    passenger = passengerSource,
    driver = driverSource,
    pickupCoords = {x, y, z},
    dropoffCoords = {x, y, z},
    pickupDistance = 250,  -- meters
    tripDistance = 1500,   -- meters
    price = 150,           -- dollars
    status = "waiting",
    vehiclePlate = "ABC123",
    driverId = "ABC12345",
    driverName = "Nguyen Van A",
    passengerId = "XYZ67890",
    passengerName = "Tran Thi B",
    createdAt = timestamp
}
```

**Server → Driver:**
```lua
TriggerClientEvent("grab:rideRequest", driverSource, rideData)
```

**Server → Passenger:**
```lua
return {
    success = true,
    message = "Đã tìm thấy tài xế! Đang chờ xác nhận...",
    rideId = rideId,
    status = "waiting"
}
```

---

### 3️⃣ Tài Xế Nhận Đơn (Driver Accept)

**Driver nhấn Y hoặc qua UI:**
```lua
TriggerServerEvent("grab:acceptRide", rideId)
```

**Server xử lý:**
1. Cập nhật status: `"waiting"` → `"picking_up"`
2. Lấy thông tin tài xế (biển số, tên, ID)

**Server → Passenger:**
```lua
TriggerClientEvent("grab:rideAccepted", passenger, {
    rideId = rideId,
    message = "Tài xế đã chấp nhận!",
    driverCoords = {x, y, z},
    vehiclePlate = "ABC123",
    driverName = "Nguyen Van A",
    driverId = "ABC12345",
    status = "picking_up"
})

TriggerClientEvent("grab:updateRideStatus", passenger, {
    status = "picking_up",
    message = "Tài xế đang đến đón bạn",
    vehiclePlate = "ABC123"
})
```

**Server → Driver:**
```lua
TriggerClientEvent("grab:startNavigation", driver, {
    coords = pickupCoords,
    type = "pickup",
    rideId = rideId
})
```

**Client Driver tạo:**
- ✅ Blip màu xanh lá tại điểm đón
- ✅ Route GPS đến điểm đón
- ✅ Thread theo dõi khoảng cách

**Client Passenger tạo:**
- ✅ Blip màu xanh dương cho tài xế
- ✅ Cập nhật UI với thông tin tài xế

---

### 4️⃣ Cập Nhật Vị Trí Realtime (Location Tracking)

**Driver client tự động gửi mỗi 3 giây:**
```lua
TriggerServerEvent("grab:updateDriverLocation", coords, inVehicle, vehiclePlate)
```

**Server → Passenger:**
```lua
TriggerClientEvent("grab:updateDriverLocation", passenger, {
    coords = {x, y, z},
    vehiclePlate = "ABC123",
    status = "picking_up"
})
```

**Passenger client:**
- Cập nhật vị trí blip tài xế
- Gửi tọa độ lên UI để hiển thị trên bản đồ

**UI nhận được:**
```javascript
{
    type: "grab:driverLocationUpdate",
    data: {
        x: 1234,
        y: 5678,
        vehiclePlate: "ABC123",
        status: "picking_up"
    }
}
```

---

### 5️⃣ Tài Xế Đến Điểm Đón (Arrived at Pickup)

**Driver client tự động phát hiện (khoảng cách < 15m):**
```lua
TriggerServerEvent("grab:arrivedAtPickup", rideId)
```

**Server xử lý:**
1. Cập nhật status: `"picking_up"` → `"in_progress"`
2. Lưu thời gian bắt đầu: `startTime = os.time()`

**Server → Passenger:**
```lua
TriggerClientEvent("grab:driverArrived", passenger)
TriggerClientEvent("grab:updateRideStatus", passenger, {
    status = "in_progress",
    message = "Tài xế đã đến! Chuyến đi bắt đầu"
})
TriggerClientEvent("grab:showDropoffLocation", passenger, {
    coords = dropoffCoords,
    rideId = rideId
})
```

**Server → Driver:**
```lua
TriggerClientEvent("grab:clearNavigation", driver)
TriggerClientEvent("grab:startNavigation", driver, {
    coords = dropoffCoords,
    type = "dropoff",
    rideId = rideId
})
```

**Client Driver:**
- ❌ Xóa blip điểm đón
- ✅ Tạo blip màu cam tại điểm trả
- ✅ Route GPS đến điểm trả
- ✅ Thread theo dõi khoảng cách đến điểm trả

**Client Passenger:**
- ❌ Xóa blip tài xế
- ✅ Tạo blip màu cam tại điểm trả
- ✅ Thread theo dõi khoảng cách đến điểm trả
- ✅ UI hiển thị "Đang trên đường đến điểm trả"

---

### 6️⃣ Đến Điểm Trả (Arrived at Dropoff)

**Driver client tự động phát hiện (khoảng cách < 15m):**
- Hiển thị thông báo: "Đã đến điểm trả khách!"
- Gửi event lên UI để hiển thị nút "Hoàn thành"

**UI nhận được:**
```javascript
{
    type: "grab:arrivedAtDropoff",
    data: {}
}
```

**Driver nhấn "Hoàn thành" trên UI:**
```lua
TriggerServerEvent("grab:completeRide", rideId)
```

---

### 7️⃣ Hoàn Thành Chuyến (Complete Ride)

**Server xử lý:**
1. Kiểm tra status = `"in_progress"`
2. Cập nhật status: `"in_progress"` → `"completed"`
3. Trả tiền cho tài xế:
```lua
Player.Functions.AddMoney("cash", price, "grab-ride-payment")
```
4. Trừ tiền khách:
```lua
PassengerPlayer.Functions.RemoveMoney("cash", price, "grab-ride-charge")
```
5. Giải phóng tài xế: `activeDrivers[driver].busy = false`
6. Xóa ride: `activeRides[rideId] = nil`

**Server → Driver:**
```lua
TriggerClientEvent("QBCore:Notify", driver, {
    text = "Hoàn thành chuyến xe!\n" ..
           "Mã chuyến: GRAB20260313120530123\n" ..
           "Quãng đường: 1.5km\n" ..
           "+ $150 Tiền mặt",
    type = "success"
})
TriggerClientEvent("grab:clearNavigation", driver)
```

**Server → Passenger:**
```lua
TriggerClientEvent("grab:rideCompleted", passenger, {
    rideId = rideId,
    price = 150,
    distance = 1500
})
TriggerClientEvent("grab:updateRideStatus", passenger, {
    status = "completed",
    message = "Chuyến đi hoàn thành",
    price = 150
})
```

**Client cleanup:**
- ❌ Xóa tất cả blips
- ❌ Xóa currentRide
- ✅ UI hiển thị màn hình hoàn thành

---

## 📊 Các Trạng Thái Chuyến Đi

| Status | Mô Tả | Driver | Passenger |
|--------|-------|--------|-----------|
| `waiting` | Chờ tài xế chấp nhận | Nhận thông báo | Chờ xác nhận |
| `picking_up` | Tài xế đang đến đón | GPS → điểm đón | Theo dõi tài xế |
| `in_progress` | Đang chở khách | GPS → điểm trả | Theo dõi hành trình |
| `completed` | Hoàn thành | Nhận tiền | Trả tiền |
| `cancelled` | Đã hủy | Giải phóng | Thông báo |

---

## 🎨 UI Events (React Messages)

### Passenger UI Events:
```javascript
// Khi đặt xe thành công
grab:rideAccepted {
    rideId, status, vehiclePlate, driverName, driverId, message
}

// Cập nhật vị trí tài xế (mỗi 3s)
grab:driverLocationUpdate {
    x, y, vehiclePlate, status
}

// Cập nhật trạng thái chuyến
grab:updateRideStatus {
    rideId, status, message, vehiclePlate, price
}

// Tài xế đã đến
grab:driverArrived {
    status: "in_progress", message
}

// Hiển thị điểm trả
grab:showDropoffLocation {
    rideId, x, y
}

// Cập nhật khoảng cách đến điểm trả
grab:updateDropoffDistance {
    distance
}

// Hoàn thành
grab:rideCompleted {
    rideId, price, distance, status: "completed"
}

// Hủy chuyến
grab:rideCancelled {
    reason, status: "cancelled"
}
```

### Driver UI Events:
```javascript
// Yêu cầu mới
grab:newRideRequest {
    rideId, passengerName, passengerId, pickupDistance, tripDistance, price
}

// Cập nhật khoảng cách
grab:updateDistance {
    distance, type: "pickup" | "dropoff"
}

// Đến điểm trả
grab:arrivedAtDropoff {}

// Cập nhật trạng thái tài xế
grab:updateDriverStatus {
    isDriver, message
}
```

---

## 🔧 Các Hàm Callback Quan Trọng

### Client → Server Callbacks:

1. **grab:requestRide**
   - Input: `pickupCoords, dropoffCoords`
   - Output: `{success, message, rideId, pickupDistance, tripDistance, price, status}`

2. **grab:getNearbyDrivers**
   - Input: `passengerCoords`
   - Output: `[{coords, distance}]`

3. **grab:getAllDrivers**
   - Input: `passengerCoords`
   - Output: `[{x, y, z, distance, busy}]`

---

## 💡 Tính Năng Nổi Bật

✅ **Mã chuyến duy nhất**: GRAB + timestamp + playerID
✅ **Thông tin đầy đủ**: Tên, ID, biển số xe
✅ **GPS 2 giai đoạn**: Điểm đón → Điểm trả
✅ **Tracking realtime**: Cập nhật vị trí mỗi 3 giây
✅ **UI chuyên nghiệp**: Hiển thị trạng thái rõ ràng
✅ **Auto-detect arrival**: Tự động phát hiện đến nơi
✅ **Blip màu sắc**: Xanh lá (đón), Cam (trả), Xanh dương (tài xế)
✅ **Tính tiền tự động**: Trả cho tài xế, trừ tiền khách

---

## 🚀 Hướng Dẫn Sử Dụng

### Cho Khách Hàng:
1. Mở app Grab trên điện thoại
2. Chọn điểm đón (mặc định vị trí hiện tại)
3. Chọn điểm trả trên bản đồ
4. Nhấn "Đặt xe"
5. Chờ tài xế chấp nhận
6. Theo dõi tài xế đang đến
7. Lên xe khi tài xế đến
8. Theo dõi hành trình đến điểm trả
9. Trả tiền khi hoàn thành

### Cho Tài Xế:
1. Bật chế độ "Tài xế Grab"
2. Chờ yêu cầu đặt xe
3. Nhấn Y để chấp nhận hoặc N để từ chối
4. Đi đến điểm đón khách (theo GPS)
5. Hệ thống tự động chuyển sang điểm trả
6. Đưa khách đến điểm trả
7. Nhấn "Hoàn thành" để nhận tiền

---

## 📝 Ghi Chú Kỹ Thuật

- Khoảng cách phát hiện đến nơi: **15 mét**
- Tần suất cập nhật vị trí: **3 giây**
- Công thức tính giá: `max(50, distance * 0.1)`
- Timeout chấp nhận đơn: **15 giây**
- Bán kính tìm tài xế: **1000 mét**
