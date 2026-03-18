# Ẩn nền trắng bên ngoài Map

## Vấn đề

Khi hiển thị toàn bộ map, có các vùng nền trắng xuất hiện bên ngoài tiles, gây mất thẩm mỹ.

## Giải pháp CSS

### 1. Đặt nền đen cho các container chính

```css
/* Full Screen Map */
.map-section {
    flex: 1;
    position: relative;
    background: #000; /* Nền đen thay vì trắng */
    overflow: hidden; /* Ẩn phần thừa */
}

.map-container {
    width: 100%;
    height: 100%;
    background: #000; /* Nền đen cho map container */
}
```

### 2. Ẩn nền trắng của Leaflet

```css
/* Ẩn nền trắng bên ngoài tiles */
.leaflet-container {
    background: #000 !important; /* Nền đen cho leaflet container */
}

.leaflet-tile-container {
    background: transparent !important;
}

/* Ẩn vùng trống bên ngoài map bounds */
.leaflet-map-pane {
    background: #000 !important;
}

.leaflet-tile-pane {
    background: transparent !important;
}
```

### 3. Đảm bảo toàn bộ app có nền đen

```css
/* Đảm bảo toàn bộ app có nền đen, không có vùng trắng */
.grab-container {
    background: #000;
}
```

### 4. Ẩn scrollbar nếu có

```css
/* Ẩn scrollbar nếu có */
.leaflet-container::-webkit-scrollbar {
    display: none;
}

.leaflet-container {
    -ms-overflow-style: none;
    scrollbar-width: none;
}
```

### 5. Responsive cho mobile

```css
/* Đảm bảo không có nền trắng trên mobile */
@media (max-width: 480px) {
    .map-section, .map-container, .leaflet-container {
        background: #000 !important;
    }
}
```

## Kết quả

- ✅ Không còn vùng nền trắng bên ngoài map
- ✅ Toàn bộ app có nền đen nhất quán
- ✅ Hoạt động tốt trên cả desktop và mobile
- ✅ Không ảnh hưởng đến chức năng map
- ✅ Tiles vẫn hiển thị bình thường

## Cách hoạt động

1. **Container backgrounds**: Đặt nền đen cho tất cả containers
2. **Leaflet overrides**: Ghi đè CSS mặc định của Leaflet
3. **Overflow hidden**: Ẩn phần thừa ra ngoài
4. **Transparent tiles**: Tile containers trong suốt
5. **Responsive**: Đảm bảo hoạt động trên mọi thiết bị

Bây giờ map sẽ hiển thị toàn bộ mà không có vùng nền trắng nào bên ngoài!