# Liquid Finance

Ứng dụng quản lý tài chính cá nhân native cho iPhone, viết bằng SwiftUI. Giao diện tiếng Việt, thiết kế thích ứng với kích thước màn hình và hỗ trợ iOS 16 trở lên.

## Tính năng

- Tổng quan số dư, thu nhập và chi tiêu theo tháng; tùy chọn ẩn số dư.
- Ghi, sửa, tìm kiếm và lọc giao dịch; phân loại thu nhập và chi tiêu.
- Nhập số tiền với dấu phân tách hàng nghìn tức thời; chọn ngày và giờ giao dịch.
- Lọc giao dịch và báo cáo theo khoảng ngày/giờ tùy chọn, hoặc xem không giới hạn.
- Lập giao dịch định kỳ theo ngày, tuần, tháng hoặc năm; quản lý, tạm dừng và xóa lịch định kỳ.
- Ngân sách theo danh mục với tiến độ và cảnh báo khi vượt giới hạn.
- Mỗi ngân sách có thể áp dụng cho một, nhiều hoặc tất cả danh mục.
- Báo cáo 6 tháng và cơ cấu chi tiêu theo danh mục.
- Danh mục cha/con có thể tùy chỉnh; ví tiền mặt, ngân hàng, thẻ và ví điện tử.
- Sao lưu/khôi phục toàn bộ dữ liệu JSON, xuất giao dịch CSV và xóa dữ liệu.
- Chọn giao diện sáng, tối hoặc tự động theo thiết bị.
- Nhắc nhập giao dịch cuối ngày với giờ do bạn chọn.
- App icon Liquid Finance, định dạng ngày giờ `dd/MM/yyyy · HH:mm`, và chọn tháng/năm trực tiếp trên màn hình Tổng quan, Giao dịch, Ngân sách và Báo cáo.
- Chọn biểu tượng khi tạo danh mục; tám danh mục dùng nhiều nhất hiển thị trước trong biểu mẫu giao dịch.
- V3.2 bổ sung chuyển khoản nội bộ, ngân sách theo tuần/tháng/quý/năm, cảnh báo mức dùng 80%, biểu đồ theo ngày hoặc tháng và widget số dư/nhập nhanh.
- V3.5 đồng bộ version trong app, extension widget, IPA và GitHub Release; kiểm tra launch screen iPhone được đóng gói.
- Widget dùng App Group `group.vn.liquidfinance`; hãy bật App Groups với định danh này cho app và widget trong Apple Developer nếu tạo IPA đã ký.
- Lưu trữ cục bộ bằng `UserDefaults`; không cần đăng nhập hoặc kết nối mạng.

## Mở bằng Xcode

Cài [XcodeGen](https://github.com/yonaskolb/XcodeGen), sau đó chạy:

```sh
xcodegen generate --spec project.yml
open LiquidFinance.xcodeproj
```

Chọn scheme `LiquidFinance` và một iPhone Simulator để chạy app hoặc bộ test `LiquidFinanceTests`.

## GitHub Actions

Workflow `.github/workflows/ios.yml` tự chọn iPhone Simulator đang có để chạy unit tests trên mỗi push và pull request. Mỗi push lên `main` hoặc `master` tạo GitHub Release theo version tăng dần `v3.5.<run>` cùng IPA có tên version đó, ví dụ `LiquidFinance-v3.5.42.ipa`. Push một tag `v3.5.0` sẽ tạo/cập nhật release và IPA mang version đó.

Nếu chưa thêm thông tin ký, release vẫn nhận IPA chưa ký; tệp chưa ký không cài trực tiếp lên iPhone thật. Để tạo IPA đã ký, thêm các repository secrets: `IOS_CERTIFICATE_BASE64` (tệp `.p12` dạng base64), `IOS_CERTIFICATE_PASSWORD`, `IOS_PROVISIONING_PROFILE_BASE64` (profile dạng base64), `IOS_PROFILE_NAME` (tên profile), và `IOS_TEAM_ID`. Secret tùy chọn `IOS_EXPORT_METHOD` nhận `ad-hoc` (mặc định), `development`, `enterprise` hoặc `app-store-connect`. Certificate, profile, team và bundle ID `vn.liquidfinance.app` phải khớp nhau.

Có thể tạo release phiên bản riêng bằng:

```sh
git tag v3.5.0
git push origin v3.5.0
```

## Kiểm thử

Unit tests kiểm tra số dư, tổng theo tháng và khoảng thời gian, cập nhật giao dịch/ngân sách, phân cấp và nhiều danh mục, định dạng số tiền, giao dịch định kỳ, số dư ví, sao lưu/khôi phục và schema backup. Chạy trên máy Mac có Xcode:

```sh
SIMULATOR_ID="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ { print $2; exit }')"
xcodebuild test -project LiquidFinance.xcodeproj -scheme LiquidFinance \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" CODE_SIGNING_ALLOWED=NO
```
