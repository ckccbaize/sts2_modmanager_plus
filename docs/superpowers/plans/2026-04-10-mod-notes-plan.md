# 模组备注功能实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**目标:** 为模组详情面板添加自定义备注功能，用户可为已安装模组添加个性化备注

**架构:** 使用独立JSON文件存储备注，UI在模组详情面板添加编辑按钮和备注展示区域

**技术栈:** Godot 4.5, GDScript, JSON

---

## 文件修改列表

- `modmanager.gd` - 添加备注数据加载/保存逻辑，UI更新
- `locales/zh_CN.json` - 添加翻译key
- `locales/en_US.json` - 添加翻译key

---

### Task 1: 添加翻译key

**Files:**
- Modify: `locales/zh_CN.json`
- Modify: `locales/en_US.json`

- [ ] **Step 1: 添加翻译key到zh_CN.json**

在 `"nexus_mod_details": "模组详情",` 后添加:
```json
"mod_note": "备注",
"mod_note_edit": "编辑备注",
"mod_note_placeholder": "点击添加备注...",
```

- [ ] **Step 2: 添加翻译key到en_US.json**

在对应位置添加:
```json
"mod_note": "Note",
"mod_note_edit": "Edit Note",
"mod_note_placeholder": "Click to add note...",
```

---

### Task 2: 添加备注数据管理变量和函数

**Files:**
- Modify: `modmanager.gd` - 在var声明区域添加变量

- [ ] **Step 1: 添加备注数据变量**

在 `modmanager.gd` 约第150行附近（var声明区域）添加:
```gdscript
# 模组备注数据
var mod_notes: Dictionary = {}  # {mod_id: note_text}
var mod_notes_file_path: String = ""
```

- [ ] **Step 2: 初始化mod_notes_file_path**

在 `get_base_path()` 函数后添加新属性:
```gdscript
var mod_notes_path: String:
	get: return get_base_path() + "mod_notes.json"
```

- [ ] **Step 3: 添加加载备注函数**

在 `load_locale()` 函数后添加:
```gdscript
# 加载模组备注
func load_mod_notes() -> void:
	var path = mod_notes_path
	if not FileAccess.file_exists(path):
		print("[load_mod_notes] File not exists, creating empty notes")
		mod_notes = {}
		return
	
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("[load_mod_notes] Open failed")
		mod_notes = {}
		return
	
	var text = file.get_as_text()
	file.close()
	
	if text.is_empty():
		mod_notes = {}
		return
	
	var json = JSON.new()
	var err = json.parse(text)
	if err != OK:
		print("[load_mod_notes] Parse failed: ", err)
		mod_notes = {}
		return
	
	var data = json.get_data()
	if data is Dictionary:
		mod_notes = data.get("mod_notes", {})
	else:
		mod_notes = {}
	print("[load_mod_notes] Loaded: ", mod_notes.size(), " notes")
```

- [ ] **Step 4: 添加保存备注函数**

在 `load_mod_notes()` 后添加:
```gdscript
# 保存模组备注
func save_mod_notes() -> void:
	var path = mod_notes_path
	
	# 确保目录存在
	var dir = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	
	var json_str = JSON.stringify({"mod_notes": mod_notes}, "\t")
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		print("[save_mod_notes] Open failed")
		return
	
	file.store_string(json_str)
	file.close()
	print("[save_mod_notes] Saved: ", mod_notes.size(), " notes")
```

- [ ] **Step 5: 在启动时加载备注**

在 `_ready()` 中约第1760行附近找到 `load_locale()` 调用，在其后添加:
```gdscript
load_mod_notes()
```

---

### Task 3: 添加备注UI（笔图标按钮和备注显示Label）

**Files:**
- Modify: `modmanager.gd` - 添加UI节点引用和创建逻辑

- [ ] **Step 1: 添加UI节点引用变量**

在 `mod_details_dep` 变量声明附近（约第248行）添加:
```gdscript
@onready var mod_note_edit_btn: Button
@onready var mod_note_label: Label
@onready var mod_note_separator: HSeparator
```

- [ ] **Step 2: 在_init_ui_nodes()中创建备注按钮和显示区域**

在 `_show_mod_details()` 函数末尾添加备注相关UI的懒加载创建:
```gdscript
# 懒加载备注编辑按钮
if not mod_note_edit_btn:
	var btn = Button.new()
	btn.name = "ModNoteEditBtn"
	btn.text = "📝"
	btn.tooltip_text = translate("mod_note_edit")
	btn.custom_minimum_size = Vector2(32, 32)
	# 添加到模组详情面板的右上角位置
	# 需要找到合适的父容器添加
	mod_note_edit_btn = btn

# 懒加载备注显示Label
if not mod_note_label:
	var lbl = Label.new()
	lbl.name = "ModNoteLabel"
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(0, 40)
	mod_note_label = lbl

# 懒加载分割线
if not mod_note_separator:
	var sep = HSeparator.new()
	sep.name = "ModNoteSeparator"
	mod_note_separator = sep
```

- [ ] **Step 3: 在_show_mod_details()中更新备注显示**

在 `_show_mod_details()` 函数末尾（约第9479行之后）添加:
```gdscript
# 显示备注（如果存在）
var mod_id = mod_data.get("id", "")
var note_text = mod_notes.get(mod_id, "")
if mod_note_label:
	if not note_text.is_empty():
		mod_note_label.text = translate("mod_note") + ": " + note_text
		mod_note_label.visible = true
		if mod_note_separator:
			mod_note_separator.visible = true
	else:
		mod_note_label.visible = false
		if mod_note_separator:
			mod_note_separator.visible = false
```

---

### Task 4: 创建备注编辑弹窗

**Files:**
- Modify: `modmanager.gd` - 添加弹窗函数

- [ ] **Step 1: 添加弹窗函数**

在文件末尾（约第12900行）添加:
```gdscript
# 显示备注编辑弹窗
func _show_mod_note_edit_dialog(mod_id: String) -> void:
	var current_note = mod_notes.get(mod_id, "")
	
	# 创建对话框
	var dialog = AcceptDialog.new()
	dialog.title = translate("mod_note_edit")
	dialog.ok_button_text = translate("confirm")
	dialog.cancel_button_text = translate("cancel")
	add_child(dialog)
	
	# 创建内容容器
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(350, 150)
	
	# 创建输入框
	var text_edit = TextEdit.new()
	text_edit.text = current_note
	text_edit.custom_minimum_size = Vector2(350, 120)
	text_edit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	
	# 字符限制提示
	var hint_label = Label.new()
	hint_label.text = "最多500字符"
	hint_label.add_theme_font_size_override("font_size", 10)
	hint_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
	
	vbox.add_child(text_edit)
	vbox.add_child(hint_label)
	dialog.add_child(vbox)
	
	# 连接信号
	dialog.confirmed.connect(func():
		var new_note = text_edit.text.strip_edges().left(500)
		if new_note.is_empty():
			mod_notes.erase(mod_id)
		else:
			mod_notes[mod_id] = new_note
		save_mod_notes()
		# 刷新显示
		_on_mod_item_selected(current_mod_data)
		dialog.queue_free()
	)
	
	dialog.canceled.connect(func():
		dialog.queue_free()
	)
	
	dialog.popup_centered(Vector2(400, 200))


# 编辑备注按钮点击处理
func _on_mod_note_edit_btn_pressed() -> void:
	if current_mod_data.is_empty():
		return
	var mod_id = current_mod_data.get("id", "")
	if not mod_id.is_empty():
		_show_mod_note_edit_dialog(mod_id)
```

- [ ] **Step 2: 连接按钮点击信号**

在 `_show_mod_details()` 中备注按钮创建后添加信号连接:
```gdscript
if mod_note_edit_btn and not mod_note_edit_btn.pressed.is_connected(_on_mod_note_edit_btn_pressed):
	mod_note_edit_btn.pressed.connect(_on_mod_note_edit_btn_pressed)
```

---

### Task 5: 添加缺失的翻译key

**Files:**
- Modify: `locales/zh_CN.json`
- Modify: `locales/en_US.json`

- [ ] **Step 1: 检查并添加缺失的翻译key**

查找现有弹窗中使用的翻译key（如confirm, cancel），确认已存在:
- `"confirm": "确认"`
- `"cancel": "取消"`

确保以上key存在于两个locale文件中。

---

## 实施总结

**Task计数:** 5个

**执行顺序:** 按Task顺序依次执行

**关键点:**
1. 注意在编辑器运行时使用`res://`路径，导出版本使用exe所在目录
2. 备注以模组id为key存储，不同版本共享
3. 500字符限制
4. 弹窗使用Godot内置AcceptDialog