# LinkPilot — Đặc tả v0.1

LinkPilot là ứng dụng menu bar cho macOS, nhận các link HTTP và HTTPS từ hệ thống. Người dùng có thể chọn browser và profile mỗi lần mở, đặt mặc định, hoặc lưu quy tắc theo tên miền. Tình huống chính là mở link vào Chrome cá nhân `Default` trong khi một phiên Chrome tự động hóa với thư mục dữ liệu khác vẫn chạy.

## Phạm vi MVP

| Tính năng | Phạm vi |
| --- | --- |
| Nhận link | HTTP và HTTPS, từ lúc app chưa chạy và khi app đang chạy |
| Đích mở link | Profile Chrome Stable trong thư mục dữ liệu cá nhân chuẩn, Safari và Firefox ở mức ứng dụng |
| Chế độ mở | Hỏi mỗi lần, mở mặc định, hoặc áp dụng quy tắc có thứ tự |
| Quy tắc | Tên miền chính xác hoặc tên miền và các subdomain, có thêm, sửa, tắt, xóa và sắp xếp |
| Picker | Chọn bằng chuột hoặc bàn phím, sao chép link, lưu lựa chọn theo hostname đang hiện |
| Cài đặt | Kiểm tra default handler, mở cài đặt hệ thống, làm mới danh sách đích, chỉnh quy tắc |

macOS 14 trở lên là baseline đề xuất. Smoke test ưu tiên Apple Silicon. Các phiên bản sau có thể thêm profile Edge, Brave và Firefox, quy tắc theo app nguồn, deep link sang app native, và `mailto:`. Tính năng mở rộng URL rút gọn, bỏ tracking, Handoff và Windows nằm ngoài MVP. Nguồn và mức xác minh nằm trong [ghi chú khảo sát](RESEARCH.md).

## Luồng người dùng

1. Mở app lần đầu. Menu bar báo trạng thái handler cho HTTP và HTTPS, hiển thị các đích hiện có và hướng dẫn đặt LinkPilot làm trình duyệt mặc định. Hệ thống giữ quyền xác nhận. Chọn chế độ hỏi mỗi lần hoặc đặt một đích mặc định.
2. Bấm link từ bất kỳ app nào. LinkPilot nhận URL và chọn quy tắc khớp đầu tiên đang bật. Nếu quy tắc khớp nhưng đích mất, mở picker với lý do. Khi không có quy tắc khớp, mở đích mặc định nếu cấu hình và đích còn sẵn. Các trường hợp còn lại hiện picker.
3. Picker hiển thị hostname, URL có thể xem đầy đủ, và danh sách đích dạng hàng với icon browser và nhãn profile. Focus nằm ở danh sách. Dùng phím mũi tên và Return để chọn, Escape để hủy, hoặc ⌘C để sao chép URL gốc và đóng picker. Nếu nhiều URL cần hỏi, xếp FIFO và hiển thị từng URL.
4. Bật **Nhớ cho tên miền này** trước khi chọn đích để lưu quy tắc hostname chính xác sau khi lệnh mở được chấp nhận. Quy tắc mới nằm trên quy tắc bao quát trước đó. Nếu đã có quy tắc hostname chính xác, cập nhật và đưa nó lên đầu. Khi lưu thất bại, báo rõ link đã được chuyển và quy tắc chưa lưu. Hủy không ghi quy tắc.
5. Nếu một đích được chọn lỗi, giữ link trong picker và cho phép thử lại hoặc chọn đích khác. Nếu chưa tìm được đích nào, vẫn cho sao chép link. Khi tắt hoặc gỡ app, người dùng đặt lại browser mặc định trong System Settings.

Thiết kế riêng của LinkPilot là cửa sổ nhỏ với hostname ở đầu, URL ngay bên dưới và danh sách đích một cột. Quản lý quy tắc ở cửa sổ Settings dạng bảng, với thứ tự hiển thị đúng thứ tự chạy.

## Quy tắc định tuyến

- Nhận URL tuyệt đối có scheme HTTP hoặc HTTPS và hostname hợp lệ. Chuẩn hóa hostname để so khớp theo chữ thường, IDNA và bỏ dấu chấm cuối. Giữ nguyên URL nhận được khi gửi đích, kể cả query, fragment, percent encoding và port.
- `exact(example.com)` chỉ khớp `example.com`. `domainAndSubdomains(example.com)` khớp thêm `docs.example.com`, theo ranh giới dấu chấm. Port không tham gia so khớp. Cho phép IP IPv4 và IPv6 ở chế độ chính xác.
- Quy tắc bật đầu tiên khớp hostname có quyền quyết định. Chế độ mặc định là `ask` hoặc `open(destinationID)`. Nếu quy tắc đầu tiên khớp có đích không còn khả dụng, yêu cầu người dùng chọn lại để tránh tự gửi nhầm browser hoặc profile.
- Giữ mỗi lần bấm là một yêu cầu riêng. Bộ nhận chuyển URL vào hàng đợi theo thứ tự nhận. Các yêu cầu cần picker chờ theo thứ tự. Báo lỗi launch bất đồng bộ cùng URL tương ứng. Từ chối mọi scheme ngoài phạm vi và loại LinkPilot khỏi danh sách đích để tránh vòng lặp.

## Kiến trúc đề xuất

App Swift native dùng AppKit cho vòng đời, nhận URL và cửa sổ picker. SwiftUI phù hợp cho Settings. Dùng `CFBundleURLTypes` khai báo HTTP và HTTPS, `NSApplicationDelegate.application(_:open:)` nhận URL, và `NSWorkspace` để kiểm tra handler. Onboarding mở cài đặt mặc định của hệ thống hoặc gọi API đăng ký handler có xác nhận khi phù hợp, sau đó kiểm tra lại riêng hai scheme. Đưa request đến bộ điều phối ngay khi app nhận được, kể cả trước khi UI sẵn sàng.

| Thành phần | Trách nhiệm |
| --- | --- |
| Registry | Tìm browser theo bundle ID, kiểm tra executable và đọc danh sách profile Chrome |
| Router | URL và cấu hình → mở đích, hỏi người dùng, hoặc từ chối. Tách khỏi UI và hệ thống để kiểm thử |
| Launcher | App thông thường dùng `NSWorkspace.open(_:withApplicationAt:configuration:completionHandler:)` chỉ định bundle URL. Chrome profile dùng `Process` trực tiếp |
| Settings store | JSON có version, ghi nguyên tử và tuần tự hóa thay đổi. Nếu lỗi hoặc version mới hơn, giữ file gốc, hiển thị lỗi và dùng chế độ hỏi cho phiên hiện tại |
| Coordinator | Khởi tạo state, quản lý hàng đợi, chạy launcher ngoài UI thread, đưa lỗi về đúng màn hình và duy trì trạng thái handler |

Registry tìm Chrome Stable qua bundle ID `com.google.Chrome` và đọc `profile.info_cache` trong `~/Library/Application Support/Google/Chrome/Local State`. Chỉ dùng thư mục profile nằm trực tiếp trong data root và còn tồn tại. Profile ghi bằng ID thư mục như `Default` và `Profile 1`. Nhãn hiển thị có thể đổi hoặc trùng nhau, vì vậy hiện thêm tên thư mục khi cần phân biệt. Dữ liệu Chrome được đọc lại lúc khởi động, trước khi hiện picker và khi validate đích để mở. Nếu metadata bị chặn, lỗi hoặc thiếu, báo trạng thái và cho chọn thư mục Chrome qua hộp thoại macOS. Khi Chrome Stable được cài, `Default` vẫn là một đích dựng sẵn bằng data root chuẩn và ID cố định. Chrome có thể tạo profile mặc định ở lần chạy đầu. Các profile đặt tên chỉ hiện khi metadata và thư mục kiểm tra được.

```text
executable = executableURL của Chrome Stable
arguments  = [
  "--user-data-dir=<absolute Chrome data root>",
  "--profile-directory=<profile directory ID>",
  "<original HTTP(S) URL>"
]
```

Dùng argv trực tiếp. Cả data root và profile ID đều cần thiết vì nhiều phiên Chrome có thể có một profile tên `Default` riêng. Kiểm tra lại đích ngay trước khi mở. Báo lỗi spawn hoặc exit code sớm khác 0. Process còn chạy sau thời gian quan sát có thể là phiên Chrome vừa khởi động. Tiếp tục nhận URL và giữ quyền theo dõi process ở nền, không chờ Chrome thoát và không tự kết thúc browser. Việc chuyển lệnh chỉ xác nhận đã gửi yêu cầu. Nghiệm thu mở đúng tab dựa trên bằng chứng trong phiên browser. Trường hợp Chrome đã chạy có bằng chứng thực nghiệm. Cold start vẫn cần xác minh.

### Cấu hình mẫu

```json
{
  "version": 1,
  "fallback": {
    "type": "open",
    "destination": {"bundleID": "com.google.Chrome", "profileDirectory": "Default"}
  },
  "rules": [
    {
      "id": "work",
      "enabled": true,
      "match": {"type": "domainAndSubdomains", "host": "example.org"},
      "destination": {"bundleID": "com.google.Chrome", "profileDirectory": "Profile 1"}
    }
  ]
}
```

Đích Safari và Firefox chỉ lưu bundle ID. LinkPilot dùng dữ liệu cục bộ, không ghi lịch sử link, URL đầy đủ hoặc query vào log. Diagnostics chỉ ghi loại sự kiện, kết quả và mã lỗi. URL chỉ tồn tại trong bộ nhớ đủ để xử lý yêu cầu. Thao tác sao chép đưa URL ra clipboard theo lựa chọn của người dùng.

## Nghiệm thu

| ID | Kiểm thử và kết quả mong đợi |
| --- | --- |
| A1 | Đặt LinkPilot mặc định, bấm link từ Ghostty và một app khác. LinkPilot nhận cả khi cold start và khi đã chạy. Kiểm tra HTTP và HTTPS độc lập, kể cả khi người dùng hủy xác nhận hoặc đổi browser mặc định |
| A2 | Bật Chrome cá nhân và phiên tự động hóa với data root riêng. Bấm link có marker dùng một lần. Marker phải xuất hiện trong Chrome cá nhân `Default`, và không có trong phiên tự động hóa |
| A3 | Lặp A2 khi Chrome cá nhân chưa chạy, chỉ có phiên tự động hóa. Lặp với `Profile 1` đang mở và kiểm tra một rule có đích khác `Default` |
| A4 | Kiểm tra exact, subdomain, thứ tự hai rule cùng match, rule tắt, case, IDNA, hostname có dấu chấm cuối, host gần giống. URL đích giữ nguyên query, fragment và encoding |
| A5 | Hai URL đến gần nhau hiện picker theo thứ tự. Test chuột, bàn phím, Escape, copy, và Remember. Mở lại app để xác thực rule còn áp dụng |
| A6 | Đổi tên profile giữ đúng đích. Xóa profile, gỡ browser hoặc làm hỏng cấu hình rồi mở link. Picker hiện lỗi có thể xử lý và không tự mở bằng profile khác |
| A7 | Xác thực URL lạ hoặc thiếu host bị từ chối, LinkPilot không tự gọi lại, URL nhạy cảm không xuất hiện trong log, lỗi ghi cấu hình không ghi đè bản cũ |
| A8 | Chọn Safari và Firefox ở mức ứng dụng khi có cài. Kiểm tra mở link hợp lệ, tình huống browser thiếu và khi người dùng đổi default handler giữa phiên |

## Trình tự triển khai

1. Spike app nhận HTTP/HTTPS và launcher Chrome có data root cố định. Qua A1–A3 trước khi xây Settings.
2. Thêm registry, router thuần và kiểm thử bảng cho A4. Sau đó thêm picker và hàng đợi.
3. Thêm quản lý cấu hình, onboarding, trạng thái lỗi và chạy toàn bộ ma trận. Chốt cách ký và phân phối sau khi bản local ổn định.
