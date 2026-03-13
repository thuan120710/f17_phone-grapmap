# Hướng dẫn cài đặt Grab App

## Tổng quan
Grab App là một ứng dụng đặt xe riêng biệt cho LB Phone, được tách riêng khỏi Maps app để có chức năng độc lập và đầy đủ hơn.

## Cấu trúc file đã tạo

### Client-side
- `client/apps/custom/grab.lua` - Logic phía client cho Grab app
- `ui/apps/grab/index.html` - Giao diện HTML của app
- `ui/apps/grab/style.css` - CSS styling cho app
- `ui/apps/grab/script.js` - JavaScript logic cho UI

### Server-side
- `server/apps/custom/grab.lua` - Logic phía server cho Grab app
- `config/grab.lua` - Cấu hình cho Grab app

### Database
- `grab_app.sql` - Script SQL để tạo bảng cơ sở dữ liệu

## Cài đặt

### 1. Chạy SQL Script
```sql
-- Chạy file grab_app.sql trong database của bạn
SOURCE grab_app.sql;
```

### 2. Cập nhật fxmanifest.lua
File đã được cập nhật để include các file UI mới:
```lua
files {
    "ui/dist/**/*",
    "ui/components.js",
    "ui/grab.html",
    "ui/apps/grab/**/*", -- Đã thêm
    "config/**/*"
}
```

### 3. Cấu hình App
App đã được đăng ký trong `config/config.lua`:
```lua
Config.CustomApps = {
    ["GrabApp"] = {
        name = "Grab F17",
        description = "Dịch vụ đặt xe Grab với GPS và theo dõi tài xế",
        developer = "F17 Team",
        defaultApp = true,
        ui = GetCurrentResourceName() .. "/ui/apps/grab/index.html",
        icon = "https://r2.fivemanage.com/nxNLB1G6HkjvgkH6kSpy9/grab-icon.png",
        -- ... các cấu hình khác
    }
}
```

## Tính năng

### Cho khách hàng:
- 🚗 Đặt xe Grab với GPS
- 📍 Xem vị trí tài xế trên bản đồ
- 💰 Xem giá ước tính
- 📱 Theo dõi trạng thái chuyến xe
- ❌ Hủy chuyến xe

### Cho tài xế:
- 🚕 Đăng ký làm tài xế
- 🟢 Bật/tắt chế độ hoạt động
- 📞 Nhận yêu cầu chuyến xe
- ✅ Chấp nhận/từ chối chuyến
- 📍 Điều hướng đến khách hàng
- 💵 Nhận tiền khi hoàn thành

### Tính năng bản đồ:
- 🗺️ Bản đồ GTA V với 3 layer (Render, Game, Print)
- 📍 Marker vị trí người chơi (xanh dương cho khách, xanh lá cho tài xế)
- 🚗 Hiển thị tất cả tài xế online
- 🔴 Phân biệt tài xế rảnh (xanh lá) và bận (đỏ)
- 📱 Theo dõi vị trí real-time

## Cấu hình

### Trong `config/grab.lua`:
```lua
Config.Grab = {
    pricePerMeter = 100,     -- Giá mỗi mét
    minimumPrice = 50,       -- Giá tối thiểu
    maximumPrice = 5000,     -- Giá tối đa
    maxSearchRadius = 1000,  -- Bán kính tìm tài xế (mét)
    arrivalDistance = 10,    -- Khoảng cách coi là "đã đến"
    requestTimeout = 15000,  -- Thời gian chờ tài xế phản hồi (ms)
    requireVehicle = true,   -- Tài xế phải trong xe mới nhận chuyến
    -- ... các cấu hình khác
}
```

## Sự khác biệt với Maps app cũ

### Ưu điểm của Grab App riêng:
1. **Tách biệt hoàn toàn**: Không ảnh hưởng đến Maps app gốc
2. **UI chuyên biệt**: Giao diện được thiết kế riêng cho Grab
3. **Chức năng đầy đủ**: Có tất cả tính năng cần thiết cho dịch vụ đặt xe
4. **Dễ bảo trì**: Code được tổ chức rõ ràng theo từng file riêng biệt
5. **Có thể mở rộng**: Dễ dàng thêm tính năng mới như rating, lịch sử chuyến xe

### Cấu trúc theo chuẩn:
- ✅ Tách client/server riêng biệt
- ✅ Có file config riêng
- ✅ UI được tổ chức trong thư mục riêng
- ✅ Database schema đầy đủ
- ✅ Error handling và validation

## Restart và test

1. Restart resource `lb-phone`
2. Mở điện thoại trong game
3. Tìm app "Grab F17" trong danh sách app
4. Test các chức năng:
   - Đăng ký tài xế
   - Đặt xe
   - Theo dõi trên bản đồ

## Lưu ý
- App này hoàn toàn độc lập với Maps app gốc
- Tất cả dữ liệu Grab được lưu trong bảng riêng
- Có thể dễ dàng tắt/bật mà không ảnh hưởng chức năng khác
- Code được viết theo chuẩn F17 với proper error handling