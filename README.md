# Liquid Finance

Ứng dụng quản lý tài chính cá nhân native cho iPhone, viết bằng SwiftUI. Giao diện tiếng Việt, thiết kế thích ứng với kích thước màn hình và hỗ trợ iOS 16 trở lên.

## Tính năng

- Tổng quan số dư, thu nhập và chi tiêu theo tháng; tùy chọn ẩn số dư.
- Ghi, sửa, tìm kiếm và lọc giao dịch; phân loại thu nhập và chi tiêu.
- Ngân sách theo danh mục với tiến độ và cảnh báo khi vượt giới hạn.
- Báo cáo 6 tháng và cơ cấu chi tiêu theo danh mục.
- Danh mục cha/con có thể tùy chỉnh; ví tiền mặt, ngân hàng, thẻ và ví điện tử.
- Sao lưu/khôi phục toàn bộ dữ liệu JSON, xuất giao dịch CSV và xóa dữ liệu.
- Chọn giao diện sáng, tối hoặc tự động theo thiết bị.
- Lưu trữ cục bộ bằng `UserDefaults`; không cần đăng nhập hoặc kết nối mạng.

## Mở bằng Xcode

Cài [XcodeGen](https://github.com/yonaskolb/XcodeGen), sau đó chạy:

```sh
xcodegen generate --spec project.yml
open LiquidFinance.xcodeproj
```

Chọn scheme `LiquidFinance` và một iPhone Simulator để chạy app hoặc bộ test `LiquidFinanceTests`.

## GitHub Actions

Workflow `.github/workflows/ios.yml` tự chọn iPhone Simulator đang có để chạy unit tests. Khi push tag phiên bản dạng `v1.0.0`, workflow build IPA, đặt tên `LiquidFinance-v1.0.0.ipa` và đính kèm vào GitHub Release tương ứng.

Nếu chưa thêm thông tin ký, release vẫn nhận IPA chưa ký `LiquidFinance-v1.0.0.ipa`; tệp chưa ký không cài trực tiếp lên iPhone thật. Để tạo IPA đã ký, thêm các repository secrets: `IOS_CERTIFICATE_BASE64` (tệp `.p12` dạng base64), `IOS_CERTIFICATE_PASSWORD`, `IOS_PROVISIONING_PROFILE_BASE64` (profile dạng base64), `IOS_PROFILE_NAME` (tên profile), và `IOS_TEAM_ID`. Secret tùy chọn `IOS_EXPORT_METHOD` nhận `ad-hoc` (mặc định), `development`, `enterprise` hoặc `app-store-connect`. Certificate, profile, team và bundle ID `vn.liquidfinance.app` phải khớp nhau.

Tạo release bằng:

```sh
git tag v1.0.0
git push origin v1.0.0
```

## Kiểm thử

Unit tests kiểm tra số dư, tổng theo tháng, cập nhật giao dịch/ngân sách, phân cấp danh mục, số dư ví, sao lưu/khôi phục và schema backup. Chạy trên máy Mac có Xcode:

```sh
SIMULATOR_ID="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ { print $2; exit }')"
xcodebuild test -project LiquidFinance.xcodeproj -scheme LiquidFinance \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" CODE_SIGNING_ALLOWED=NO
```
