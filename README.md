# ScriptHub Pro — GitHub Pages + Supabase

Bản này có đăng ký/đăng nhập, hồ sơ, đăng script, sửa script của mình, thích, bình luận, bảng xếp hạng, thông báo bình luận, báo cáo và trang quản trị.

## A. Tạo backend Supabase
1. Tạo project tại https://supabase.com.
2. Vào **SQL Editor → New query**.
3. Mở `schema.sql`, copy toàn bộ và chạy.
4. Vào **Project Settings → API** (hoặc API Keys), lấy:
   - Project URL
   - anon/public key (publishable/anon key)
5. Mở `index.html`, thay:
   - `PASTE_SUPABASE_PROJECT_URL_HERE`
   - `PASTE_SUPABASE_ANON_KEY_HERE`
   bằng giá trị của project.
6. Không bao giờ dán `service_role` / secret key vào HTML, GitHub hoặc gửi cho người khác.

## B. Tạo tài khoản admin
1. Mở website sau khi đã cấu hình Supabase.
2. Đăng ký tài khoản bằng email của bạn và xác nhận email nếu Supabase yêu cầu.
3. Trong Supabase **SQL Editor**, chạy câu lệnh cuối file `schema.sql` sau khi thay email:
   ```sql
   update public.profiles
   set is_admin = true
   where id = (select id from auth.users where email = 'EMAIL_CUA_BAN');
   ```
4. Đăng xuất rồi đăng nhập lại. Tab Admin sẽ xuất hiện.
5. Không cấp quyền admin cho tài khoản khác trừ khi bạn tin tưởng họ.

## C. Đưa lên GitHub Pages
1. Tạo repository mới trên GitHub.
2. Upload `index.html`, `schema.sql`, `README.md` vào thư mục gốc.
3. Mở **Settings → Pages**.
4. Chọn **Deploy from a branch**, branch `main`, folder `/(root)`, rồi Save.
5. Đợi GitHub Pages deploy và mở URL được cung cấp.

## D. Thiết lập Auth nên làm
Trong Supabase **Authentication → URL Configuration**:
- Site URL: URL GitHub Pages của bạn.
- Redirect URLs: thêm chính xác URL GitHub Pages (bao gồm đường dẫn repo nếu có).
Trong **Authentication → Providers → Email**:
- Có thể bật xác nhận email để hạn chế tài khoản rác.
- Khi thử nghiệm, kiểm tra email xác nhận và redirect URL.

## E. Cách hoạt động
- GitHub Pages host file HTML tĩnh.
- Supabase Auth quản lý đăng nhập.
- PostgreSQL lưu profile, scripts, likes, comments, notifications, reports.
- Trigger SQL tự tạo profile khi đăng ký và tạo thông báo khi có người khác bình luận vào script.
- RLS (Row Level Security) giới hạn người dùng chỉ sửa hồ sơ của mình, chỉ sửa/xóa script của mình; admin có thể kiểm duyệt.
- Thông báo được cập nhật khi mở trang thông báo và bộ đếm được làm mới định kỳ.

## F. Lưu ý trước khi công khai
Đây là bộ khởi đầu có thể triển khai, không phải nền tảng chống spam hoàn chỉnh:
- Bật CAPTCHA/rate limit cho đăng ký, bình luận và báo cáo.
- Bổ sung quy trình xử lý báo cáo và chính sách cộng đồng.
- Kiểm tra quota Supabase và sao lưu dữ liệu.
- Đường dẫn ảnh đại diện phải là URL ảnh tin cậy; bản này chưa có upload ảnh lên Storage.
- Bảng xếp hạng hiện tính theo tổng lượt thích, không phải điểm đánh giá chất lượng.
- RLS cho phép đọc profile/script công khai; bình luận và lượt thích yêu cầu đăng nhập.
- Khi triển khai production, cân nhắc thêm pagination, lọc nội dung, chống spam, audit log và xác minh tài khoản.

## Files
- `index.html`: toàn bộ giao diện + logic frontend.
- `schema.sql`: bảng dữ liệu, trigger, index và RLS policies.
