# Hệ thống Grab - Hướng dẫn cài đặt

## Tổng quan
Hệ thống Grab được tích hợp vào app Maps của LB Phone, cho phép người chơi:

**Tài xế Grab:**
- Đăng ký/hủy đăng ký chạy Grab
- Hiển thị vị trí trên bản đồ khi online
- Nhận thông báo khi có khách đặt xe
- Chỉ đường đến vị trí khách hàng
- Nhận tiền sau khi hoàn thành chuyến

**Khách hàng:**
- Đặt xe trong app Maps
- Tự động tìm tài xế gần nhất
- Theo dõi trạng thái chuyến xe

## Cài đặt

### 1. Database
Chạy file `grab.sql` để tạo bảng cần thiết:
```sql
-- Import grab.sql vào database
```

### 2. Files đã được sửa đổi
- `client/apps/default/maps.lua` - Thêm logic Grab client
- `server/apps/default/maps.lua` - Thêm logic Grab server  
- `ui/dist/assets/Maps-6f0d30bc.js` - Thêm UI Grab vào Maps

### 3. Không cần sửa fxmanifest.lua
Tất cả code đã được tích hợp vào Maps app có sẵn.

## Cách sử dụng

### Cho tài xế:
1. Mở app Maps trên điện thoại
2. Chuyển sang tab "Tài Xế" 
3. Bấm "Đăng Ký Chạy Grab"
4. Phải ngồi trong xe để nhận chuyến
5. Khi có yêu cầu, ấn Y để chấp nhận, N để từ chối
6. Đi đến vị trí khách hàng (có GPS chỉ đường)
7. Bấm "Hoàn Thành" khi xong chuyến

### Cho khách hàng:
1. Mở app Maps trên điện thoại
2. Ở tab "Đặt Xe"
3. Bấm "Đặt Xe Ngay"
4. Hệ thống tự động tìm tài xế gần nhất
5. Chờ tài xế đến đón

## Tính năng

### Hệ thống tính tiền:
- 100$ mỗi mét khoảng cách
- Tài xế nhận tiền mặt khi hoàn thành

### Hệ thống thông báo:
- Thông báo realtime cho cả tài xế và khách
- Hiển thị trạng thái chuyến xe
- GPS chỉ đường cho tài xế

### Bảo mật:
- Kiểm tra tài xế phải trong xe
- Xử lý disconnect của người chơi
- Tự động hủy chuyến khi có lỗi

## Lưu ý
- Tài xế phải ngồi trong xe mới nhận được chuyến
- Hệ thống tự động cập nhật vị trí tài xế mỗi 5 giây
- Tài xế có 15 giây để phản hồi yêu cầu đặt xe
- Khoảng cách tối đa tìm tài xế: 1000m

## Troubleshooting
- Nếu UI không hiển thị: Kiểm tra file Maps-6f0d30bc.js đã được inject code
- Nếu không nhận được thông báo: Kiểm tra exports['f17notify'] hoạt động
- Nếu không nhận tiền: Kiểm tra QBCore.Functions.GetPlayer và AddMoney