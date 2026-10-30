# Kiểm chứng

Bản phân phối ngày 30/10/2026. Source Swift/Kotlin không đổi so với hai file đã tích hợp và kiểm tra trong app demo.

## Build và kiểm tra tự động

- Xcode: iOS Simulator và generic iOS device build thành công. Device build tắt code signing, không phải IPA có thể cài lên iPhone thật.
- Swift motion checks: 12 hướng chuyển, retarget liên tục, press/release/cancel, 2–5 tab, input 30/60/120Hz và Reduce Motion đều đạt.
- Android: `:app:testDebugUnitTest :app:assembleDebug --offline` thành công, 8 tests, 0 failures/errors.
- APK demo đã cài lên Pixel 7 và Pixel 10 Emulator.
- App iOS không có file `default.metallib` bên ngoài; shader nhúng chạy được trên iOS 26.3 và iOS 27 Simulator.

## Giao diện và thao tác

- Cả hai nền tảng: chọn tab cuối trong 6 cấu hình gồm 4+action, 3+action, 2+action, 3, 2 và 5 tab không action. Ảnh [iOS](media/ios-layouts.jpg) / [Android](media/android-layouts.jpg) chụp sau settle.
- Video README được quay mới từ bản component đã đóng gói: iOS 27 Coral/light và Android 17 Coral/dark.
- iOS: giữ, swipe qua khoảng cách xa, quay lại và chạm chọn. Android: kéo 1.8 giây mỗi hướng từ Home đến Account và quay lại.
- iOS 26.3 đã thử mở action riêng sau khi chuyển tab. Các trang trong bản ghi là dữ liệu mẫu.

## Phạm vi chưa kiểm tra

- Chưa đo FPS, jank hoặc độ trễ bằng Instruments/Macrobenchmark.
- Chưa chạy trên iPhone thật; chưa visual QA fallback Android API 31–32.
- XCTest UI runner ở môi trường demo không khởi chạy được; không tính suite đó là đã đạt. Kiểm tra giao diện trên đây thực hiện qua thao tác thiết bị và xem bản ghi.
- RTL hiện không tự mirror; thứ tự tab từ trái sang phải theo danh sách.
- Swift giữ cây view của các tab. Compose giữ state saveable; state chỉ dùng `remember` sẽ không được giữ khi trang rời composition.

Các kết quả trên thuộc demo tích hợp, không phải CI đang chạy trong repository này.
