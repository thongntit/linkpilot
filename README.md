# LinkPilot

Ứng dụng menu bar cho macOS. LinkPilot nhận link từ các ứng dụng, tự mở theo quy tắc hoặc cho bạn chọn browser và profile.

## Tải bản build từ GitHub

Workflow [macOS](https://github.com/thongntit/linkpilot/actions/workflows/macos.yml) chạy test và build khi có pull request, khi push lên `main`, hoặc khi chạy thủ công. Đăng nhập GitHub, mở lần chạy thành công và tải artifact **LinkPilot-macos-arm64**. Giải nén `LinkPilot-macos-arm64.zip` để lấy `LinkPilot.app`. Bản CI dành cho Apple Silicon, ký ad hoc và chưa notarize.

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
