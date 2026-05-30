--- rx_value.lua
--- 轻量级响应式状态管理库
--- 
--- 本库参考 Vue 3 响应式原理实现，提供 ref、computed、watchEffect、watch 以及深层响应式对象 (reactive)。
--- 适用于 Unity + Lua 框架中的 UI 数据绑定、状态管理、副作用隔离等场景。
--- 
--- ## 设计理念
--- - 依赖收集与触发更新完全基于「发布-订阅」模式。
--- - 每个响应式数据（ref / computed）维护一个依赖列表 `_deps`，其中存储所有依赖它的副作用 effect。
--- - 全局变量 `activeEffect` 指向当前正在执行的 effect，保证依赖自动收集。
--- - 修改数据时，遍历依赖列表并执行 effect，从而实现自动更新。
--- 
--- ## 响应式核心原理
--- 
--- ### 1. Ref 响应式值
--- `ref` 包装一个普通值，返回带有 `get()` 和 `set()` 方法的对象。
--- - `get()`：若当前存在 `activeEffect`，则将该 effect 加入当前 ref 的依赖列表中，然后返回内部值。
--- - `set(newValue)`：更新内部值，若值改变则遍历依赖列表，依次调用每个 effect 的 `run()` 方法，触发更新。
--- 
--- ### 2. Computed 计算属性
--- 本库中 `computed` 采用「无缓存、懒求值」策略，每次调用 `:get()` 都会重新执行 getter 函数。
--- - 不维护内部缓存和脏标记，逻辑极为简单，完全避免了因缓存失效导致的依赖追踪错误。
--- - 依赖收集完全依赖于 `watchEffect` 或 `ref:get` 中的 `activeEffect` 机制：当外部 effect 读取 computed 时，
---   computed 的 getter 内部访问的其他响应式数据会将该 effect 加入其依赖列表，从而形成完整的通知链。
--- - 当依赖变化时，effect 重新运行，再次读取 computed 即获得最新值。
--- 
--- ### 3. Effect 副作用与 watchEffect
--- `watchEffect` 创建一个 effect，立即执行一次传入的函数，并将自身设为全局 `activeEffect`。
--- - 执行期间，所有被访问的响应式数据（ref / computed）都会将该 effect 加入其 `_deps`。
--- - 当这些数据发生变化时，会遍历 `_deps` 并调用 effect 的 `run` 方法，从而重新执行副作用函数。
--- - effect 内部会自动清理旧的依赖关系，避免内存泄漏和无效触发。
--- 
--- ### 4. Watch 观察者
--- `watch` 基于 `watchEffect` 实现，可以监听一个 ref、一个 getter 函数或一个数组，并在数据变化时执行回调。
--- - 支持获取新值和旧值。
--- - 可通过 `options.immediate` 控制是否立即执行回调。
--- - 内部通过比较新旧值决定是否触发回调，避免无意义的调用。
--- 
--- ### 5. Reactive 深层响应式对象
--- `reactive` 将一个普通表转换为深度响应式代理。
--- - 通过元表劫持 `__index` 和 `__newindex` 实现。
--- - 访问属性时自动创建对应的 ref 并缓存，读取返回 `ref:get()`，写入调用 `ref:set()`。
--- - 支持嵌套对象递归代理，保持整个对象图的响应性。
--- - 可选参数 `onChange` 可作为全局变化回调（用于框架集成）。
--- 
--- ## 使用示例
--- 
--- ### 基础使用：ref 与 watchEffect
--- ```lua
--- local rx = require "rx_value"
--- local count = rx.ref(0)
--- local text = rx.ref("hello")
--- 
--- rx.watchEffect(function()
---     print("count =", count:get(), "text =", text:get())
--- end)
--- 
--- count:set(1)   -- 输出 "count = 1 text = hello"
--- text:set("world") -- 输出 "count = 1 text = world"
--- ```
--- 
--- ### 计算属性 computed
--- ```lua
--- local double = rx.computed(function()
---     return count:get() * 2
--- end)
--- 
--- rx.watchEffect(function()
---     print("double =", double:get())
--- end)
--- 
--- count:set(2)   -- 输出 "double = 4"（因为 effect 重新运行，重新读取 double:get()）
--- ```
--- 
--- ### 使用 watch
--- ```lua
--- rx.watch(count, function(newVal, oldVal)
---     print("count changed from", oldVal, "to", newVal)
--- end, { immediate = true })
--- 
--- count:set(10)  -- 输出 "count changed from 2 to 10"
--- ```
--- 
--- ### 深层响应式对象
--- ```lua
--- local state = rx.reactive({ user = { name = "Alice", age = 25 } })
--- rx.watchEffect(function()
---     print(state.user.name, state.user.age)
--- end)
--- 
--- state.user.name = "Bob"   -- 触发打印 "Bob 25"
--- state.user.age = 30       -- 触发打印 "Bob 30"
--- ```
--- 
--- ### 与 UI 绑定框架集成（例如自动生成的 DataBinding 插件）
--- 本库专为 UI 数据绑定设计，生成的绑定代码会使用 `watchEffect` 监听 `view.states` 中的响应式数据，
--- 并在数据变化时自动更新 UI 控件属性。具体可参考 `DataBindingPlugin` 生成的 Lua 绑定代码。
--- 
--- ## 注意事项
--- 1. **computed 无缓存**：每次调用 `:get()` 都会重新求值，不适合计算开销极大的场景。但在 UI 绑定中完全够用。
--- 2. **依赖收集必须在 effect 中进行**：直接在全局环境下调用 `ref:get()` 不会收集任何依赖，也不会建立响应关系。
--- 3. **避免在 effect 中修改同一数据造成死循环**：例如在 `watchEffect` 中同时读写同一个 ref 可能引发无限递归，本库通过 `_running` 标志防止重入。
--- 4. **手动清理**：`watchEffect` 返回一个停止函数，建议在组件销毁时调用，避免内存泄漏。
--- 5. **reactive 与 ref 混用**：`reactive` 返回的代理对象中的属性已经是响应式的，但若需传递单个值，仍建议使用 `ref`。
--- 
--- ## 许可证
--- MIT License
--- 
--- @author lyt0628
--- @release 1.0.0


local M = {}

-- ========== 全局依赖管理 ==========
local activeEffect = nil
local effectStack = {}
local nextId = 0
local function getNextId()
    nextId = nextId + 1
    return nextId
end

-- ========== Ref 实现 ==========
local Ref = {}
Ref.__index = Ref

function Ref:get()
    if activeEffect then
        activeEffect:addDep(self)
    end
    return self._value
end

function Ref:set(newValue)
    if self._value == newValue then
        return
    end
    self._value = newValue
    if self._deps then
        local depsCopy = {}
        for i, dep in ipairs(self._deps) do
            depsCopy[i] = dep
        end
        for _, dep in ipairs(depsCopy) do
            dep:run()
        end
    end
end

function Ref:addDep(effect)
    if not self._deps then
        self._deps = {}
    end
    for _, e in ipairs(self._deps) do
        if e == effect then
            return
        end
    end
    table.insert(self._deps, effect)
end

function M.ref(initialValue)
    local self = setmetatable({}, Ref)
    self._value = initialValue
    self._id = getNextId()
    return self
end

function M.isRef(val)
    return getmetatable(val) == Ref
end

function M.unwrap(val)
    if M.isRef(val) then
        return val:get()
    end
    return val
end

-- ========== 计算属性 Computed（简化版，无缓存，每次求值） ==========
local ComputedRef = {}
ComputedRef.__index = ComputedRef

function ComputedRef:get()
    -- 直接调用 getter 返回计算结果，不做缓存
    -- 依赖收集由 getter 中访问的 ref 自动完成（通过 activeEffect）
    return self._getter()
end

function M.computed(getter)
    local self = setmetatable({}, ComputedRef)
    self._getter = getter
    return self
end

-- ========== Effect 副作用 ==========
local Effect = {}
Effect.__index = Effect

function Effect:run()
    if self._running then
        return
    end
    self._running = true

    if self._deps then
        for _, dep in ipairs(self._deps) do
            if dep and dep._deps then
                for i, e in ipairs(dep._deps) do
                    if e == self then
                        table.remove(dep._deps, i)
                        break
                    end
                end
            end
        end
        self._deps = {}
    end

    local prevEffect = activeEffect
    activeEffect = self
    table.insert(effectStack, self)

    local success, err = pcall(self._fn)
    if not success then
        print("[rx_value] Effect error:", err)
    end

    table.remove(effectStack)
    activeEffect = prevEffect
    self._running = false
end

function Effect:addDep(dep)
    if not self._deps then
        self._deps = {}
    end
    for _, d in ipairs(self._deps) do
        if d == dep then
            return
        end
    end
    table.insert(self._deps, dep)
    dep:addDep(self)
end

function M.watchEffect(fn)
    local effect = setmetatable({}, Effect)
    effect._fn = fn
    effect._running = false
    effect._deps = nil
    effect:run()
    return function()
        if effect._deps then
            for _, dep in ipairs(effect._deps) do
                if dep and dep._deps then
                    for i, e in ipairs(dep._deps) do
                        if e == effect then
                            table.remove(dep._deps, i)
                            break
                        end
                    end
                end
            end
            effect._deps = nil
        end
    end
end

function M.watch(source, callback, options)
    local getter
    if type(source) == "function" then
        getter = source
    elseif M.isRef(source) then
        getter = function() return source:get() end
    elseif type(source) == "table" then
        getter = function()
            local res = {}
            for i, s in ipairs(source) do
                res[i] = M.isRef(s) and s:get() or s
            end
            return res
        end
    else
        error("watch source must be a Ref, a function, or an array of Refs")
    end

    local oldValue
    local firstRun = true
    return M.watchEffect(function()
        local newValue = getter()
        if firstRun then
            oldValue = newValue
            firstRun = false
            if options and options.immediate then
                callback(newValue, nil)
            end
        else
            local changed = false
            if type(newValue) == "table" and type(oldValue) == "table" then
                if #newValue ~= #oldValue then
                    changed = true
                else
                    for i, v in ipairs(newValue) do
                        if v ~= oldValue[i] then
                            changed = true
                            break
                        end
                    end
                end
            else
                changed = newValue ~= oldValue
            end
            if changed then
                callback(newValue, oldValue)
                oldValue = newValue
            end
        end
    end)
end

-- ========== Reactive (深层响应式对象) ==========
local reactiveCache = setmetatable({}, { __mode = "k" })

local function isPlainTable(v)
    return type(v) == "table" and getmetatable(v) == nil
end

local function createReactive(target, onChange)
    if type(target) ~= "table" then
        return target
    end
    if getmetatable(target) and getmetatable(target).__isReactive then
        return target
    end
    if reactiveCache[target] then
        return reactiveCache[target]
    end

    local refs = {}
    local proxy = {}

    for key, value in pairs(target) do
        if isPlainTable(value) then
            local subProxy = createReactive(value, onChange)
            refs[key] = subProxy
        end
    end

    local mt = {
        __isReactive = true,
        __index = function(_, key)
            local val = refs[key]
            if val ~= nil then
                if M.isRef(val) then
                    return val:get()
                else
                    return val
                end
            end
            local rawVal = target[key]
            if rawVal == nil then
                return nil
            end
            if isPlainTable(rawVal) then
                local subProxy = createReactive(rawVal, onChange)
                refs[key] = subProxy
                return subProxy
            else
                local r = M.ref(rawVal)
                refs[key] = r
                if onChange then
                    M.watchEffect(function()
                        r:get()
                        onChange()
                    end)
                end
                return r:get()
            end
        end,
        __newindex = function(_, key, value)
            local existing = refs[key]
            local newVal = value
            if isPlainTable(value) then
                newVal = createReactive(value, onChange)
            end
            if existing then
                if M.isRef(existing) then
                    existing:set(newVal)
                else
                    refs[key] = newVal
                    target[key] = value
                    if onChange then onChange() end
                end
            else
                local r = M.ref(newVal)
                refs[key] = r
                target[key] = value
                if onChange then
                    M.watchEffect(function()
                        r:get()
                        onChange()
                    end)
                end
                if onChange then onChange() end
            end
        end,
        __pairs = function()
            return function(t, key)
                local nextKey = next(target, key)
                if nextKey ~= nil then
                    return nextKey, t[nextKey]
                end
                return nil
            end
        end,
        __len = function()
            return #target
        end,
    }
    setmetatable(proxy, mt)
    reactiveCache[target] = proxy
    return proxy
end

function M.reactive(tbl, onChange)
    if type(tbl) ~= "table" then
        error("reactive expects a table")
    end
    return createReactive(tbl, onChange)
end

function M.isReactive(val)
    local mt = getmetatable(val)
    return mt and mt.__isReactive == true
end

return M
