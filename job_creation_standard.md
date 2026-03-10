---
description: Hướng dẫn tiêu chuẩn tạo nghề mới dựa trên f17_nghesach
---

# Workflow Tạo Nghề Mới (f17_nghesach)

Tài liệu này là quy chuẩn và các bước hướng dẫn chi tiết để tạo ra một nghề mới dựa trên cấu trúc của thư mục `f17_nghesach`.

## 1. Cấu trúc thư mục (Folder Structure)
Mỗi nghề mới cần phân tách rõ ràng thành 3 phần chính trong `f17_nghesach`:
- **`client/[ten_nghe]/client.lua`**: Chứa toàn bộ logic phía người chơi (Tạo Blips, vòng lặp Thread vẽ Marker, NPC, DrawText3D, Progressbars, Animations...).
- **`server/[ten_nghe]/server.lua`**: Chứa xử lý dữ liệu và bảo mật (Khai báo AntiTrigger_VoKy, Add/Remove Items, nhận/tính toán phần thưởng, và thao tác Database).
- **`shared/`**: Có thể chứa cấu hình dùng chung (nếu cần chia sẻ biến dùng chung giữa các script).

---

## 2. Ghi chú cấu hình (fxmanifest & config.lua)

### 2.1 fxmanifest.lua
Bất kỳ nghề nào thêm vào phải được khai báo chống dump và đường dẫn chạy trong `fxmanifest.lua`:
```lua
-- Chống dump file client (BẮT BUỘC)
VoKy_AntiLoader {
    'client/grabfood/client.lua',
    'client/thodien/client.lua',
    'client/[ten_nghe_moi]/client.lua' -- Khai báo file client của nghề ở đây
}

-- Chỉ nạp các server_scripts trong đúng thư mục
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'main_sv.lua',
    'server/**/*.lua' -- Đã trỏ sẵn, không cần sửa
}
```

### 2.2 config.lua
File config chứa thông tin NPC hoặc điểm xuất phát của nghề. Khi thêm nghề, hãy đăng ký 1 Location theo MẪU:
```lua
Config.Locations = {
    ["NPC_TeNghề"] = {
        -- name: Chuẩn format "~y~[XX Lv]~w~ Nghề [Tên Nghề]" (thêm chữ COOP nếu là nghề đồng đội)
        -- coords: Vị trí của NPC
        -- sprite: ID icon blip trên map
        { name = "~y~[10 Lv]~w~ Nghề Test", coords = vector4(x, y, z, w), sprite = 208, col = 0, scale = 1.2, blipTrue = true },
    },
}
```

---

## 3. Quản lý túi đồ (ox_inventory)
Mọi tương tác thêm/bớt vật phẩm **phải sử dụng `ox_inventory`** và tuyệt đối phải kiểm tra logic cân nặng/số ô túi đồ.

### Mẫu kiểm tra và Add/Remove Item
Sử dụng `ox = exports.ox_inventory` ở server.lua
```lua
-- 1. Xóa vật phẩm (RemoveItem)
local removed = ox:RemoveItem(src, "ten_vat_pham_can", so_luong)
if not removed then
    exports['f17notify']:Notify(src, "Bạn không đủ vật phẩm để làm điều này!", "error", 5000)
    return
end

-- 2. Kiểm tra túi đồ trước khi nhận vật phẩm mới (CanCarryItem)
local canCarry, message = ox:CanCarryItem(src, "ten_vat_pham_nhan", so_luong)
if not canCarry then
    exports['f17notify']:Notify(src, message, "error", 5000) -- Thông báo túi đầy
    -- Lưu lại vật phẩm chưa nhận vào pending cache (nếu cần)
    return
end

-- 3. Thêm vật phẩm (AddItem)
local success = ox:AddItem(src, "ten_vat_pham_nhan", so_luong)
if success then
    -- Thực hiện thông báo thành công
end
```
*Lưu ý: Với các nghề rớt nhiều loại items khác nhau ngẫu nhiên (như Thợ Mỏ), cần sử dụng thuật toán tính toán chia lô (Batch) hoặc hàm custom `checkInv` để duyệt qua tổng cân nặng (Weight) và số ô trống (Empty Slots).*

---

## 4. Cơ chế AddXP
XP nhân vật sẽ được tính qua sự kiện `f17-level:client:AddPlayerXP` nhưng cần dựa theo hệ số bổ trợ (P) (từ hệ thống BĐVL nếu có).
```lua
-- Ví dụ hàm lấy XP
local p = promise.new()
local check = GlobalState.BDVL and GlobalState.BDVL.vieclam and GlobalState.BDVL.vieclam.[id_nghe]
-- check.xp và check.price sẽ ảnh hưởng đến kết quả
-- Tính toán random/bonus XP trước khi set

-- Gửi sự kiện tăng XP:
TriggerClientEvent("f17-level:client:AddPlayerXP", src, xp_tinh_toan_duoc)
```

---

## 5. Cơ chế Update JobLevel (Tiến trình nghề)
Dữ liệu level nghề được lưu ở DB trong bảng `f17_joblevel`. Mỗi lần người chơi đạt được x1 mốc khai thác, bạn phải cập nhật SQL:

```lua
-- 1. Cập nhật tiến độ số lần khai thác
local count = 1
MySQL.update.await('UPDATE f17_joblevel SET [nghe]_currentcount = [nghe]_currentcount + ?, [nghe]_totalcount = [nghe]_totalcount + ? WHERE citizenid = ?', { count, count, cid })

-- 2. Cập nhật thanh tiến độ Nhiệm Vụ Hàng Ngày (F2)
exports['f17_nhiemvu']:UpdateMissionProgress(src, 'daynghesach', 'ns_[nghe]', count)

-- 3. Cập nhật điểm thành tích Leaderboard (nếu nghề nằm trong bảng Xếp Hạng)
exports['f17_leaderboard']:UpdateAchivement(src, '[nghe]', count)
```

---

## 6. Mẫu chung khi dùng Notify
Khuyến khích sử dụng 2 dạng Notify chuẩn sau:

**A. Dành cho thông báo ngắn (dạng Popup) - Dùng f17notify:**
```lua
-- Phía Server
exports['f17notify']:Notify(src, "Nội dung nhanh gọn lẹ", "success", 5000)

-- Phía Client
exports['f17notify']:Notify("Nội dung nhanh gọn lẹ", "error", 5000)
```

**B. Dành cho thông báo dài, danh sách nhận phần thưởng - Dùng QBCore:Notify:**
Trình bày text với format có màu sắc rõ ràng (Green = Tiền/Tên vật phẩm, Yellow = Tên nghề, Blue = Buff bdvl):
```lua
local itemName = ox:Items("ten_vat_pham_nhan").label
local notifyText = "~y~[Tên Nghề]~w~ Bạn nhận được:\n+ ~g~1x "..itemName.."~s~\n+ ~g~$"..tien.." Tiền IC~s~\n+ ~g~"..xp.." XP~s~"

TriggerClientEvent("QBCore:Notify", src, notifyText, "success", 10000)
```

---

## 7. Các tiện ích UI/UX (Blip, Marker, Text3D, NPC, Progressbars)
Trong cấu trúc `f17_nghesach`, để hiển thị giao diện khi người chơi tương tác nghề nghiệp, bạn sử dụng các mẫu hàm (formula) chuẩn dưới đây:

### A. Vẽ Blip động trên bản đồ (Nhiệm vụ/Giao hàng/Sửa chữa)
Các Blip tĩnh (NPC) thường tự được nạp qua `Config.Locations`. Nếu bạn cần đánh dấu tọa độ làm việc trên bản đồ (và cần GPS tới đó), thực hiện:

```lua
local MissionBlip = nil
local function addBlip(vitri)
    MissionBlip = AddBlipForCoord(vitri.x, vitri.y, vitri.z)
    SetBlipSprite(MissionBlip, 164) -- ID icon phù hợp với nghề nghiệp
    SetBlipDisplay(MissionBlip, 4)
    SetBlipScale(MissionBlip, 0.8)
    SetBlipAsShortRange(MissionBlip, false)
    SetBlipColour(MissionBlip, 43) -- Màu sắc
    SetBlipRoute(MissionBlip, true) -- Hiển thị đường đi GPS
    SetBlipRouteColour(MissionBlip, 2)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName("~y~[Tên Nghề]~w~ Vị Trí Làm Việc")
    EndTextCommandSetBlipName(MissionBlip)
end

-- Khi xong việc, xóa blip:
-- RemoveBlip(MissionBlip)
```

### B. Vẽ DrawMarker (Vòng sáng dưới đất)
Sử dụng trong một `CreateThread` vòng lặp khi người chơi trong bán kính nhận diện `< 10.0 mét`.
```lua
local dst = #(coords - vector3(vitri.x, vitri.y, vitri.z))
if dst < 10.0 then
    -- Type 1 là vòng dẹt (Sử dụng phổ biến), tọa độ Z trừ đi 0.99 để ép sát mặt đất
    -- Thông số tỷ lệ size là 3 tham số sau màu sắc: X: 2.0, Y: 2.0, Z: 2.0
    -- Thông số màu RGB: 26 (Red), 124 (Green), 173 (Blue), 100 (Alpha - Độ trong suốt)
    DrawMarker(1, vitri.x, vitri.y, vitri.z - 0.99, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2.0, 2.0, 2.0, 26, 124, 173, 100, false, true, 2, false, false, false, false)
end
```

### C. Vẽ DrawText3D (Văn bản nổi trong không gian 3D)
Hiển thị khi người chơi tiến lại rất gần checkpoint (thường `< 1.5 mét`) để hướng dẫn phím thao tác. Hàm `DrawText3D` được cung cấp sẵn từ hệ thống `shared`.
```lua
if dst < 1.5 then
    DrawText3D(vitri.x, vitri.y, vitri.z + 0.5, "Ấn ~g~[E]~w~ để thực hiện thao tác")
    
    if IsControlJustReleased(0, 38) and not block then -- 38 là phím E
        -- Chờ xử lý logic progressbar, gán block = true để khóa thao tác
    end
end
```

### D. Progressbar (Thanh hiển thị tiến trình thời gian)
Khi người chơi ấn [E], tiến trình sẽ khởi chạy chuẩn QBCore. Có thể nạp thêm Cờ lê/Búa hoặc Animation trước progressbar:
```lua
exports["rpemotes"]:EmoteCommandStart("clipboard") -- Bắt đầu Animation

QBCore.Functions.Progressbar("ten_hanh_dong", "Đang sửa chữa...", 10000, false, false, {
    disableMovement = true,
    disableCarMovement = true,
    disableMouse = false,
    disableCombat = true,
}, {}, {}, {}, function() 
    -- callback Khi Hoàn Thành Cây Progress
    exports["rpemotes"]:EmoteCancel(true)
    ClearPedTasks(PlayerPedId())
    -- TriggerServerEvent gọi phát thưởng hoặc Next Step
end, function() 
    -- callback Khi người chơi tự Hủy 
    exports["rpemotes"]:EmoteCancel(true)
    ClearPedTasks(PlayerPedId())
    -- Xóa cờ block
end)
```

### E. Sinh và quản lý tương tác với NPC (Ped làm việc)
NPC nghề sinh ra thông qua `Config.Locations` và một central script của hệ thống sẽ cho phép tương tác. Trong script `client` của bạn, bạn chỉ cần lắng nghe Event mở menu khi chọn vào NPC.
```lua
-- Ví dụ trong F17, target menu hoặc npc menu sẽ kích hoạt event này
RegisterNetEvent("f17_[tennghe]:cl:OpenJobsMenu", function()
    local dlv = QBCore.Functions.GetPlayerData().metadata.danglamviec
    if dlv == "none" or dlv == "Tên Nghề" then
        -- Mở giao diện nghề từ hệ thống f17-jobs
        TriggerEvent('f17-jobs:cl:OpenJobsMenu', '[tennghe]')
    else
        exports['f17notify']:Notify("Bạn đang làm việc "..dlv..", vui lòng kết thúc công việc trước!", "error", 5000)
    end
end)
```
Tận dụng các khối mã trên giúp đảm bảo UX/UI đồng nhất với cơ bản hệ thống của F17.
