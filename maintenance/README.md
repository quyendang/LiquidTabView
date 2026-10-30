# Shader source

`liquidLens.metal` là source của shader icon đã nhúng trong `LiquidTabView.swift`. Không cần thêm file này vào app khi dùng component.

SwiftUI sử dụng hai thư viện Metal được biên dịch riêng cho iPhone và Simulator, minimum iOS 26.0, rồi lưu dạng Base64 trong `LiquidLensShader`. Nếu thay shader, phải biên dịch lại cho cả hai target và thay cả hai khối dữ liệu; đổi Swift tint/icon/tab không cần bước này.

Android giữ AGSL trực tiếp trong `LiquidTabView.kt`. Hai shader dùng cùng ý tưởng khúc xạ nhưng không phải mã nội bộ hoặc thuật toán được cung cấp bởi Apple.
