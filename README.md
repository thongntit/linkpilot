# LinkPilot

Ứng dụng menu bar cho macOS. LinkPilot nhận link từ các ứng dụng, tự mở theo quy tắc hoặc cho bạn chọn browser và profile.

## Chạy trên máy

Cần macOS 14 trở lên và bộ công cụ Swift 6.0 trở lên.

```sh
./scripts/build-app.sh
open dist/LinkPilot.app
```

1. Trong **LinkPilot Settings → General**, chọn **Set LinkPilot as Default…** và xác nhận trong macOS. Nếu cần, mở **Desktop & Dock Settings → Default web browser** và chọn **LinkPilot**.
2. Để tự mở mọi link chưa có quy tắc, chọn **Google Chrome · Default** ở mục **When no rule matches**. Chọn **Ask every time** để dùng picker.
3. Thêm quy tắc trong tab **Rules**, hoặc bật **Remember for this hostname** khi chọn đích trong picker. App áp dụng quy tắc khớp đầu tiên.

Nếu macOS hạn chế đọc danh sách profile, Chrome Default vẫn dùng được. Để hiện thêm profile, chọn **Choose Chrome Profile Folder…** trong General và chọn `~/Library/Application Support/Google/Chrome` bằng hộp thoại của macOS.

Bản local được ký ad hoc. Chạy kiểm thử bằng `swift test`.

[Đặc tả sản phẩm và kỹ thuật](SPEC.md) · [Bằng chứng khảo sát](RESEARCH.md)
