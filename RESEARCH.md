# Khảo sát Switchbar và Finicky

## Câu hỏi khảo sát

App nhận link macOS bằng cách nào, hỗ trợ chọn đích và lưu quy tắc ra sao, và điều kiện nào cần để mở đúng profile Chrome khi có nhiều phiên Chrome chạy song song?

| Câu hỏi | Bằng chứng | Quyết định trong LinkPilot |
| --- | --- | --- |
| App nhận link ở cấp hệ thống? | Bundle Switchbar đăng ký HTTP và HTTPS. Main bundle Electron có handler `open-url`. Source Finicky kiểm tra handler và dùng `NSWorkspace` để yêu cầu thay đổi handler theo scheme | Native AppKit nhận HTTP/HTTPS, kiểm tra riêng từng scheme |
| Chọn browser/profile và nhớ lựa chọn? | Hành vi do trang Switchbar mô tả, gồm picker, quy tắc tên miền và lưu trực tiếp từ picker | Picker bàn phím và tự lưu rule chính xác theo hostname |
| Rule và đích profile được cấu hình ra sao? | Tài liệu Finicky v4 mô tả browser mặc định, handlers, matcher và profile. Launcher đọc cấu hình profile rồi gọi lệnh hệ thống | Rule có thứ tự, đích cấu hình bằng bundle ID và thư mục profile ổn định |
| Đích Chrome có được phân biệt giữa các data root? | Thử nghiệm local mở URL có marker bằng executable Chrome với hai tham số. Marker chỉ có trong Chrome cá nhân `Default` trong các phiên đã kiểm tra | Chỉ định cả data root và profile ID cho Chrome Stable. Kiểm thử lại qua handler thật sau khi build |

## Switchbar 33.0.1 cho macOS

Đã tải DMG universal từ trang chính thức, mount chỉ đọc và kiểm tra tĩnh. `Info.plist` khai báo `http`, `https`, `mailto`, `switchbar` và `x-choosy`. Gói chứa `Contents/Resources/app.asar`. `package.json` trỏ tới `build/electron-main/electron.js`. Trong member này, kiểm tra tĩnh thấy listener Electron `open-url` và nhánh Chromium thêm `--profile-directory` vào danh sách tham số truyền cho hàm gọi child process. Kết quả cho thấy app có đường xử lý URL và có sử dụng tham số profile. Thứ tự ưu tiên rule thực tế và kết quả route trong ca nhiều data root chưa được đo. [Trang sản phẩm](https://webcatalog.io/en/switchbar) · [Trang tải macOS](https://webcatalog.io/en/switchbar/install/macos)

- DMG SHA-256 `f678f64fd22bd1fb8cb9d99ce7262b52596bca8e4802647c576e4f2e193261d8`.
- ASAR SHA-256 `32844dee9f34f399966dc4d6610d76b19a31fae49ca9a064f012ec2004f0805f`.
- REA 6.10.1, `inspect-artifact` với `--detail summary`. Inventory ghi nhận 487 file và 17 thư mục. Bằng chứng gốc `ev_742f430f15f60a05ac2481aa7e5946e86ca2a99f58f5411f71d8afd200bbe647`.
- REA `analyze-javascript-application` parse thành công main bundle đã chọn. Kết quả tĩnh có phạm vi một file và giới hạn đồ thị ngữ nghĩa. Bằng chứng gốc `ev_f33c3c94d54f7751f2d991e97f7d56f322219ad622bc03170790553a27fd25f3`. Các nhận xét về `open-url` và tham số launch được đối chiếu trực tiếp trong member đó.
- Lần kiểm tra mặc định dừng vì hash khai báo của member native đi kèm `build/native/safari-helper` khác dữ liệu thực. Lần kiểm tra sau dùng `--integrity-policy record-and-continue`, giữ kết quả đó ở trạng thái chưa thể tin cậy. Kết luận của spec không dựa trên helper này.

Email client, deep link, bỏ tracking, mở rộng link rút gọn và Handoff là các tính năng được hãng công bố. Đợt khảo sát này chưa chạy Switchbar hoặc thay đổi app mặc định trên máy.

## Finicky v4

Đọc tài liệu và source tại commit `678bb135599c063f7fc8f0ce9d6f1e22bcb7df6b`. Source macOS có API đọc và yêu cầu đặt default URL handler. Launcher dùng `open` với app chỉ định. Khi resolve được profile Chromium, nó thêm `-n`, `--args` và `--profile-directory`. Registry Chromium đọc metadata profile từ `Local State` trong data root chuẩn của browser. Nhánh cấu hình Firefox có cơ chế khác. Không suy ra việc chạy Finicky sẽ giải quyết được ca hai Chrome data root chỉ từ source. [Tài liệu v4](https://github.com/johnste/finicky/wiki/Configuration-(v4)) · [Launcher](https://github.com/johnste/finicky/blob/678bb135599c063f7fc8f0ce9d6f1e22bcb7df6b/apps/finicky/src/browser/launcher.go) · [Handler macOS](https://github.com/johnste/finicky/blob/678bb135599c063f7fc8f0ce9d6f1e22bcb7df6b/apps/finicky/src/browser.m)

## Đối chứng trên máy hiện tại

1. Mở URL thử qua `NSWorkspace` trong lúc Chrome cá nhân và Chrome tự động hóa đang chạy. Callback trả PID của Chrome tự động hóa.
2. Gọi trực tiếp executable của Google Chrome, truyền `--user-data-dir` trỏ tới Chrome cá nhân, `--profile-directory=Default` và URL thử có marker riêng.
3. Tìm đúng marker trong các file session. Marker xuất hiện trong Chrome cá nhân `Default`. Không tìm thấy marker trong hai profile Chrome tự động hóa kiểm tra được hoặc hai profile Chrome cá nhân còn lại.

Đối chứng xác nhận launcher cho tình huống Chrome cá nhân đã chạy. Tình huống Chrome cá nhân chưa chạy, lần mở qua handler LinkPilot và luồng picker là tiêu chí nghiệm thu của bản triển khai.

## Lặp lại phần REA

Sau khi mount DMG chỉ đọc, chạy từ thư mục nghiên cứu riêng với Node phiên bản REA hỗ trợ. Thay `$SWITCHBAR_ASAR` bằng đường dẫn tuyệt đối của ASAR. Tên output phải chưa tồn tại.

```sh
npx -y -p node@24.22.1 -p rea-agents@6.10.1 \
  rea inspect-artifact "$SWITCHBAR_ASAR" \
  --integrity-policy record-and-continue --detail summary \
  --evidence_output switchbar-inventory --json

npx -y -p node@24.22.1 -p rea-agents@6.10.1 \
  rea analyze-javascript-application "$SWITCHBAR_ASAR" \
  --integrity-policy record-and-continue \
  --source-path build/electron-main/electron.js \
  --detail summary --evidence_output switchbar-main-bounded \
  --analysis-timeout-ms 35000 --max-semantic-nodes 1500 \
  --max-semantic-nodes-per-file 1500 --json
```

[Reverse Engineer Anything](https://github.com/morluto/rea/tree/72bdcad49d1e6d89d935d1a493e0434b3f5d5fd7)
