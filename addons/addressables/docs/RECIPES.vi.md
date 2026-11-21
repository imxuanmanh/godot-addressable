# Công thức sử dụng

Các trường hợp tối giản, copy là dùng được. Mọi trường hợp đều giả định bạn đã có service ở mục 1 (`assets`).
Bản tiếng Anh: [RECIPES.md](RECIPES.md). Hướng dẫn đầy đủ: [USAGE.md](USAGE.md);
chi tiết từng hàm: [API.md](API.md). Các trường hợp này được kiểm chứng bằng các test trong `testbed/`.

## 1. Khởi tạo service một lần

```gdscript
var assets := Addressables.new()
add_child(assets)                                   # Bắt buộc nằm trong scene tree.
var catalog = JSON.parse_string(FileAccess.get_file_as_string("res://addressables/catalog.json"))
var issue := assets.configure(catalog, content_root) # Thư mục local hoặc thư mục https://.
assert(issue.is_empty(), issue)
```

`res://addressables/catalog.json` được chèn vào bản export sau khi bạn build content.
Trong editor, truyền `true` làm tham số thứ ba để đọc thẳng từ nguồn (không dùng pack).
Chỉ configure một lần; dùng một service cho cả game.

## 2. Nạp một asset rồi release

```gdscript
var handle := assets.load_asset("res://skins/knight.tscn", "PackedScene") # Key hoặc AddressableReference.
await handle.wait()
var scene := handle.get_result() as PackedScene     # null nếu lỗi, xem handle.error.
if scene:
	add_child(scene.instantiate())
handle.release()                                    # Luôn release, kể cả handle bị lỗi.
```

## 3. Một trận đấu: nạp bộ skin, dùng, rồi release

```gdscript
# Vào trận.
var scope := assets.create_scope()
if not await scope.load_all(skin_keys):             # Lỗi thì lô này tự được hoàn tác.
	scope.release()
	return
for key in skin_keys:
	holder.add_child((scope.get_handle(key).get_result() as PackedScene).instantiate())

# Hết trận.
holder.queue_free()                                 # Xoá instance và bỏ các tham chiếu của bạn.
scope.release()                                     # Trả lại các token.
```

RAM chỉ giảm sau khi làm đủ hai bước, thứ tự nào cũng được. Release scope trong khi
instance còn sống thì texture của chúng chưa được giải phóng.

## 4. Asset dùng chung

```gdscript
var a := assets.create_scope()
var b := assets.create_scope()
await a.load_all([key])
await b.load_all([key])                             # Cùng key: chỉ một bản trong bộ nhớ.
a.release()                                         # Vẫn còn nạp: b đang giữ.
b.release()                                         # Giờ mới giải phóng (khi không còn ai tham chiếu).
```

## 5. Tải trước khi mở một tính năng

```gdscript
var bytes := await assets.get_download_size_async(keys)   # 0 nếu đã có cache, -1 nếu key không tồn tại.
if bytes > 0:
	show_download_prompt(bytes)
var issue := await assets.download_dependencies(keys)     # Chỉ tải và kiểm tra; không mount, không nạp.
```

Nên dùng `get_download_size_async`: bản đồng bộ tính hash ngay trên luồng gọi nên có thể làm đứng hình.

## 6. Xử lý nạp lỗi

```gdscript
var handle := assets.load_asset(key)
await handle.wait()
if handle.get_result() == null:
	push_error("%s: %s" % [handle.status, handle.error])  # Sai key, sai hash, thiếu pack...
handle.release()
```

`is_done` và `progress == 1.0` cũng đúng khi lỗi; hãy kiểm tra `get_result()`.

## 7. Skin có dependency trực tiếp (đóng gói cùng skin)

```text
skin_direct.tscn --instance--> bullet.tscn       # Không cần khai báo gì thêm.
Group "skin_direct": roots = [skin_direct.tscn]
```

Bullet nằm trong pack của skin, được nạp cùng skin và giải phóng cùng skin.
Chỉ cần nạp skin: `assets.load_asset("res://skins/skin_direct.tscn")`.

## 8. Skin gọi bullet bằng reference (nạp khi cần)

```gdscript
# skin.gd (nằm trong bản gốc của game)
@export var bullet: AddressableReference            # Kéo scene bullet vào ô này trong Inspector.

# Lúc chạy
var shot := assets.load_asset(skin_node.bullet)     # Đến lúc này bullet mới được nạp.
await shot.wait()
# ...dùng shot.get_result()...
shot.release()
```

```text
Group "skin":   roots = [skin.tscn]
Group "bullet": roots = [bullet.tscn]            # Bắt buộc. Thiếu thì lúc chạy báo "Unknown address".
```

Reference chỉ là một chuỗi nên builder không lần theo nó. Target không khai báo sẽ nằm lại
trong bản export gốc, và lúc build không có cảnh báo nào.

## 9. Build và export

Trong editor: chọn resource build, rồi **Project > Tools > Build selected Addressable Content**.
Dòng lệnh:

```text
godot --headless --path . --script res://addons/addressables/editor/build_cli.gd -- res://build.tres
python addons/addressables/editor/export_cli.py --godot GODOT --project . --preset "Windows" --output build/game.exe --mode debug
```

Build lại content trước mỗi lần export. `target_platform` của build phải khớp nền tảng export
(mỗi nền tảng một resource build). Đưa các pack sinh ra lên content root của bạn.

## 10. Tắt service

```gdscript
scope.release()                                     # Release các token của bạn trước.
await assets.shutdown()                             # Đóng và chờ các lần nạp/tải đang chạy xong.
assets.queue_free()
```

## Nguyên tắc nhớ nhanh

- Release mọi handle và scope, kể cả cái bị lỗi.
- Xoá instance và xoá biến tham chiếu, nếu không RAM vẫn giữ nguyên.
- Mỗi file chỉ có một chủ: bản gốc của game hoặc một group, không cả hai.
- Script (`.gd`, `.cs`) luôn nằm trong app; pack chỉ chứa dữ liệu.
- Kiểm tra việc giao pack bằng bản export, không dùng editor.
