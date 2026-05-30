

# rx_value

轻量级响应式状态管理库，支持 数据绑定、状态管理与副作用隔离。

基于 **发布-订阅** 模式，提供 `ref`、`computed`、`watchEffect`、`watch` 以及深层响应式对象 `reactive`，原理来自 Vue 3 响应式Api。

## 安装

将 `rx_value.lua` 放入项目的 Lua 路径中，通过 `require` 引入：

```lua
local rx = require("rx_value")
```

## 核心概念

### 1. Ref — 响应式值

用 `ref(initialValue)` 包装一个普通值，返回带有 `:get()` 和 `:set(newValue)` 的对象。

- **读取**：调用 `:get()` 时，若当前有正在执行的副作用（effect），会自动将该副作用添加为依赖。
- **写入**：调用 `:set(value)` 时，若值发生变化，通知所有依赖该 ref 的副作用重新运行。

```lua
local count = rx.ref(0)
count:set(1)
print(count:get()) -- 1
```

### 2. Computed — 计算属性（无缓存版）

`computed(getter)` 创建一个计算属性，每次调用 `:get()` 都会**重新执行 getter 函数**。  
没有内部缓存与脏标记，逻辑简单，适合 UI 绑定场景。

依赖收集仍通过 getter 内部访问的 ref 自动完成。

```lua
local double = rx.computed(function()
    return count:get() * 2
end)
print(double:get()) -- 2（假设 count = 1）
```

### 3. Effect 与 watchEffect

`watchEffect(fn)` 创建一个副作用，立即执行传入的函数，并自动收集函数内部访问的所有响应式数据作为依赖。  
当依赖变化时，副作用函数会重新执行。

```lua
rx.watchEffect(function()
    print("count =", count:get())
end)
-- 修改 count 后自动打印
```

返回一个 `stop` 函数，调用后可手动停止该副作用，避免内存泄漏。

### 4. Watch — 观察者

`watch(source, callback, options)` 监听一个 ref、一个 getter 函数或一个数组，在数据变化时执行回调，并提供新旧值。

- `source`：可以是 ref 对象、getter 函数，或包含多个 ref 的数组。
- `callback(newValue, oldValue)`：变化时触发。
- `options.immediate = true`：立即执行一次回调。

### 5. Reactive — 深层响应式对象

`reactive(table, onChange?)` 将普通表转换为深度响应式代理，所有属性的读写都会被自动拦截并转为 ref 管理。  
支持嵌套对象的递归代理，可传递可选的 `onChange` 回调，用于全局变化通知。

```lua
local state = rx.reactive({ user = { name = "Alice" } })
print(state.user.name) -- Alice
state.user.name = "Bob" -- 自动触发依赖的副作用
```

## API 文档

### `rx.ref(initialValue)`
创建一个响应式引用。

- 返回对象包含 `:get()` 和 `:set(value)`。

### `rx.isRef(val)`
判断一个值是否为 `ref` 对象。

### `rx.unwrap(val)`
若 `val` 是 ref，返回其内部值；否则直接返回 `val`。

### `rx.computed(getter)`
创建一个计算属性，每次调用 `:get()` 都会重新计算。

- **注意**：无缓存，会反复执行 getter，不适合高开销计算。

### `rx.watchEffect(fn)`
创建副作用，立即执行 `fn`，并自动追踪依赖。

- 返回停止函数 `stop()`，清除该副作用的所有依赖。

### `rx.watch(source, callback, options?)`
监听数据源变化并触发回调。

- `source`：ref 对象、getter 函数、或包含多个 ref 的数组。
- `callback(newVal, oldVal)`：变化回调。
- `options.immediate`：若为 `true`，首次立即执行回调，此时 `oldVal` 为 `nil`。
- 返回停止函数。

### `rx.reactive(table, onChange?)`
将普通表转换为深度响应式代理。

- `onChange(changedKey?)`：可选，每次任意属性被修改时触发。
- 返回代理对象，可直接读写属性，无需 `.value`。

### `rx.isReactive(val)`
判断一个值是否为 `reactive` 返回的代理对象。

## 使用示例

### 基础 ref + watchEffect

```lua
local rx = require("rx_value")
local name = rx.ref("Alice")
local age = rx.ref(25)

rx.watchEffect(function()
    print(name:get(), age:get())
end)

age:set(26)
-- 输出: Alice 26
```

### 计算属性

```lua
local fullInfo = rx.computed(function()
    return name:get() .. " is " .. age:get() .. " years old"
end)

rx.watchEffect(function()
    print(fullInfo:get())
end)

name:set("Bob")
-- 输出: Bob is 26 years old
```

### watch 监听变化

```lua
rx.watch(age, function(newVal, oldVal)
    print("age changed from " .. oldVal .. " to " .. newVal)
end)

age:set(30)
-- 输出: age changed from 26 to 30
```

### 监听多个 ref

```lua
local stop = rx.watch({name, age}, function(newVals, oldVals)
    print("name or age changed")
end)
```

### 深层响应式对象

```lua
local state = rx.reactive({
    player = {
        hp = 100,
        mp = 50
    }
})

rx.watchEffect(function()
    print("HP:", state.player.hp, "MP:", state.player.mp)
end)

state.player.hp = 80
-- 输出: HP: 80 MP: 50
```

### 配合 onChange 回调

```lua
local uiState = rx.reactive({ visible = true }, function()
    print("UI state changed, refresh UI")
end)

uiState.visible = false
-- 输出: UI state changed, refresh UI
```

## 注意事项

1. **computed 无缓存**：每次 `:get()` 都会重新计算，不适合计算量非常大的场景。
2. **依赖收集必须在 effect 内**：在 `watchEffect`、`watch` 的回调或 `computed` 的 getter 外部访问 ref 不会建立响应关系。
3. **避免死循环**：不要在副作用中同时读写同一个 ref，否则可能引发无限递归。库内部通过 `_running` 标志防止重入，但仍需注意逻辑合理性。
4. **手动清理**：在组件销毁或不再需要时，调用 `watchEffect` 或 `watch` 返回的 `stop` 函数，避免内存泄漏。
5. **reactive 与 ref 混用**：`reactive` 代理的属性已经是响应式的，但如果需要传递单个值（如作为组件 prop），建议仍使用 `ref`。
6. **性能**：深层响应式代理会递归创建 ref，对于极大且深层嵌套的对象请评估性能影响。

## 许可证

MIT License
