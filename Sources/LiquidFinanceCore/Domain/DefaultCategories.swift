import Foundation

public struct DefaultCategoryGroup: Sendable {
    public let key: String, name: String, kind: CategoryKind, icon: String, color: String, children: [String]
}

/// Default student-oriented taxonomy (spec §5). Debt principal, transfers and savings are NOT
/// categories: they are separate transaction types and never count as consumer spending.
public enum DefaultCategories {
    private static func e(_ k: String, _ n: String, _ i: String, _ c: String, _ ch: [String]) -> DefaultCategoryGroup {
        .init(key: "exp.\(k)", name: n, kind: .expense, icon: i, color: c, children: ch)
    }
    private static func i(_ k: String, _ n: String, _ ic: String, _ c: String, _ ch: [String]) -> DefaultCategoryGroup {
        .init(key: "inc.\(k)", name: n, kind: .income, icon: ic, color: c, children: ch)
    }
    public static let all: [DefaultCategoryGroup] = [
        e("food", "Ăn uống", "fork.knife", "#FF9F0A", ["Ăn sáng", "Ăn trưa", "Ăn tối", "Ăn vặt", "Cà phê và trà sữa", "Đồ uống", "Đặt đồ ăn", "Ăn uống bên ngoài"]),
        e("home", "Nhà ở và sinh hoạt", "house", "#5E5CE6", ["Tiền thuê trọ", "Điện", "Nước", "Internet", "Gas", "Vệ sinh", "Đồ dùng sinh hoạt", "Sửa chữa và bảo trì"]),
        e("study", "Học tập", "book", "#0A84FF", ["Học phí", "Sách và giáo trình", "Văn phòng phẩm", "In ấn và photocopy", "Khóa học", "Phần mềm học tập", "Thi cử và chứng chỉ", "Dụng cụ học tập"]),
        e("move", "Di chuyển", "bus", "#30B0C7", ["Xăng xe", "Gửi xe", "Xe buýt", "Taxi và xe công nghệ", "Bảo dưỡng xe", "Sửa chữa xe", "Phí cầu đường", "Di chuyển khác"]),
        e("personal", "Cá nhân", "tshirt", "#FF6482", ["Quần áo", "Giày dép", "Mỹ phẩm", "Chăm sóc da", "Cắt tóc", "Vệ sinh cá nhân", "Phụ kiện", "Đồ dùng cá nhân"]),
        e("health", "Sức khỏe", "heart", "#FF453A", ["Khám bệnh", "Thuốc", "Nha khoa", "Chăm sóc sức khỏe", "Thể thao và tập luyện", "Bảo hiểm"]),
        e("fun", "Giải trí", "gamecontroller", "#BF5AF2", ["Xem phim", "Trò chơi", "Âm nhạc", "Du lịch", "Đi chơi", "Sở thích cá nhân", "Dịch vụ giải trí trực tuyến"]),
        e("tech", "Công nghệ và dịch vụ số", "iphone", "#64D2FF", ["Điện thoại", "Phụ kiện công nghệ", "Thiết bị điện tử", "Ứng dụng", "Phần mềm", "Lưu trữ đám mây", "Dịch vụ thuê bao", "Internet và dịch vụ số khác"]),
        e("social", "Gia đình và xã hội", "gift", "#FFD60A", ["Quà tặng", "Sinh nhật", "Hiếu hỉ", "Đóng góp gia đình", "Từ thiện", "Giao lưu bạn bè", "Chi phí xã hội khác"]),
        e("finance", "Tài chính", "building.columns", "#8E8E93", ["Phí ngân hàng", "Phí chuyển khoản", "Lãi vay", "Thanh toán nợ", "Bảo hiểm tài chính", "Chi phí tài chính khác"]),
        e("other", "Khác", "ellipsis.circle", "#98989D", ["Chi phí phát sinh", "Chi phí chưa phân loại"]),
        i("family", "Gia đình", "person.2", "#32D74B", ["Tiền bố mẹ chu cấp", "Tiền người thân hỗ trợ", "Trợ cấp gia đình"]),
        i("work", "Công việc", "briefcase", "#0A84FF", ["Lương làm thêm", "Lương thực tập", "Freelance", "Công việc bán thời gian", "Thu nhập kinh doanh"]),
        i("study", "Học tập", "graduationcap", "#5E5CE6", ["Học bổng", "Trợ cấp học tập", "Giải thưởng", "Hỗ trợ nghiên cứu"]),
        i("personal", "Cá nhân", "person", "#FF9F0A", ["Tiền được tặng", "Bán đồ cá nhân", "Tiền hoàn lại", "Thu nhập khác"]),
        i("finance", "Tài chính", "chart.line.uptrend.xyaxis", "#30B0C7", ["Lãi tiết kiệm", "Lãi đầu tư", "Thu nhập tài chính khác"]),
        i("other", "Khác", "ellipsis.circle", "#98989D", ["Thu nhập chưa phân loại"]),
    ]
}
