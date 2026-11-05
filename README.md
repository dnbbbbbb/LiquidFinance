# Liquid Finance

Ứng dụng quản lý tài chính cá nhân native cho iPhone, viết bằng SwiftUI. Giao diện tiếng Việt, thiết kế thích ứng với kích thước màn hình và hỗ trợ iOS 16 trở lên.

## Tính năng

- Tổng quan số dư, thu nhập và chi tiêu theo tháng; tùy chọn ẩn số dư.
- Ghi, sửa, tìm kiếm và lọc giao dịch; phân loại thu nhập và chi tiêu.
- Ngân sách theo danh mục với tiến độ và cảnh báo khi vượt giới hạn.
- Báo cáo 6 tháng và cơ cấu chi tiêu theo danh mục.
- Số dư ban đầu, nhiều đơn vị tiền để hiển thị, xuất giao dịch CSV và xóa dữ liệu.
- Lưu trữ cục bộ bằng `UserDefaults`; không cần đăng nhập hoặc kết nối mạng.

## Mở bằng Xcode

Cài [XcodeGen](https://github.com/yonaskolb/XcodeGen), sau đó chạy:

```sh
xcodegen generate --spec project.yml
open LiquidFinance.xcodeproj
```

Chọn scheme `LiquidFinance` và một iPhone Simulator để chạy app hoặc bộ test `LiquidFinanceTests`.

## GitHub Actions

Workflow `.github/workflows/ios.yml` tự chọn một iPhone Simulator đang có trên runner để chạy unit tests, tránh cố định tên máy có thể đã bị gỡ khỏi image, rồi tạo artifact IPA. Có thể tải artifact trong phần **Actions → workflow run → Artifacts**.

Nếu chưa thêm thông tin ký, workflow đóng gói `LiquidFinance-unsigned.ipa` để kiểm tra build. Để Actions tạo IPA cài được/phát hành, thêm các repository secrets: `IOS_CERTIFICATE_BASE64` (tệp `.p12` dạng base64), `IOS_CERTIFICATE_PASSWORD`, `IOS_PROVISIONING_PROFILE_BASE64` (profile dạng base64), `IOS_PROFILE_NAME` (tên profile), và `IOS_TEAM_ID`. Secret tùy chọn `IOS_EXPORT_METHOD` nhận `ad-hoc` (mặc định), `development`, `enterprise` hoặc `app-store-connect`. Certificate, profile, team và bundle ID `vn.liquidfinance.app` phải khớp nhau.

## Kiểm thử

Các unit test kiểm tra số dư, tổng theo tháng, sửa giao dịch, lưu/đọc dữ liệu và cập nhật ngân sách. Chạy trên máy Mac có Xcode:

```sh
SIMULATOR_ID="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ { print $2; exit }')"
xcodebuild test -project LiquidFinance.xcodeproj -scheme LiquidFinance \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" CODE_SIGNING_ALLOWED=NO
```
