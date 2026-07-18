# 书源编写规则

本目录只编写 `source/*.json` 书源。书源只描述站点抓取规则。

字段结构以 `docs/book-source-schema.md` 为唯一 schema 参考。该文档只描述
`references/reader-master` 当前 `BookSource` 数据结构；本文件只补充
`novel.koplugin` 可执行的规则子集和书源编写流程。

## 书源结构

- 只使用当前 `BookSource` schema，不编写或保留旧版字段。
- 单个书源文件默认是一个 JSON 对象；只有明确需要批量导入时才使用对象数组。
- 必须包含：
  - `bookSourceName`
  - `bookSourceUrl`
  - `bookSourceType`
  - `ruleSearch` 或 `ruleExplore`
  - `ruleBookInfo`
  - `ruleToc`
  - `ruleContent`
- `bookSourceType` 默认写 `0`。不要把 audio / image / file 类型当成文本小说链路可用。
- `bookSourceUrl` 写站点根地址或稳定唯一键，必须带 `http://` 或 `https://`。
- `bookSourceName` 写用户可识别的站点名；`bookSourceGroup` 可写 `"本地书源"` 或指定分组。
- 顶层 `header` 必须是 JSON 字符串，例如 `"{\"User-Agent\":\"Mozilla/5.0\"}"`。
- 单个 URL 的请求选项写在 URL 后的 `,{...}` JSON 中。
- schema 只约束字段结构，不代表 Reader 的任意 JavaScript、WebView、XPath、
  JSONPath 或正则规则都能由插件执行。
- 不拼接展示文本：标题、作者、简介、更新时间、字数、分类、最新章节分别写入对应字段。

能稳定提取的字段应尽量补齐，不只满足最小链路。优先补：

- 列表：`name`、`author`、`bookUrl`、`intro`、`coverUrl`、`kind`、`lastChapter`、`updateTime`、`wordCount`
- 详情：`name`、`author`、`intro`、`kind`、`coverUrl`、`tocUrl`、`lastChapter`、`updateTime`、`wordCount`
- 目录：`chapterName`、`chapterUrl`、`isVolume`、`isVip`、`updateTime`、`nextTocUrl`
- 正文：`content`、`nextContentUrl`

## 基础模板

```json
{
  "bookSourceName": "",
  "bookSourceGroup": "本地书源",
  "bookSourceUrl": "https://example.com/",
  "bookSourceType": 0,
  "customOrder": 0,
  "enabled": true,
  "enabledExplore": true,
  "respondTime": 180000,
  "header": "{\"User-Agent\":\"Mozilla/5.0\"}",
  "searchUrl": "",
  "exploreUrl": "",
  "ruleSearch": {
    "bookList": "",
    "name": "",
    "author": "",
    "intro": "",
    "bookUrl": "",
    "coverUrl": "",
    "kind": "",
    "lastChapter": "",
    "updateTime": "",
    "wordCount": ""
  },
  "ruleExplore": {
    "bookList": "",
    "name": "",
    "author": "",
    "intro": "",
    "bookUrl": "",
    "coverUrl": "",
    "kind": "",
    "lastChapter": "",
    "updateTime": "",
    "wordCount": ""
  },
  "ruleBookInfo": {
    "name": "",
    "author": "",
    "intro": "",
    "kind": "",
    "coverUrl": "",
    "tocUrl": "",
    "lastChapter": "",
    "updateTime": "",
    "wordCount": ""
  },
  "ruleToc": {
    "chapterList": "",
    "chapterName": "",
    "chapterUrl": "",
    "isVolume": "",
    "isVip": "",
    "updateTime": "",
    "nextTocUrl": ""
  },
  "ruleContent": {
    "content": "",
    "nextContentUrl": "",
    "sourceRegex": "",
    "replaceRegex": ""
  },
  "bookSourceComment": ""
}
```

删除确实不用的空字段；不要删除必需链路对象。

## 可依赖能力

### 请求

- 支持 `http://`、`https://`。
- 支持有限次重定向；相对链接按最终 URL 补全。
- GET query 和 POST form body 会按 `charset` 做 URL 编码；书源里写原始文本和模板变量，不要手工预编码中文。
- 已有合法 `%XX` 会保留。
- 支持 `utf-8`、`gbk`、`gb2312`、`cp936`、`gb18030`。
- 默认请求头会补 `User-Agent: KOReader` 和 `Accept-Encoding: identity`。
- 顶层 `header` 与 URL options 里的 `headers` 都可设置请求头；header 名大小写不敏感。
- 支持同源 Cookie 持久化；显式 `Cookie` 优先于已保存同名 Cookie。
- Cookie 支持常用 `Domain`、`Path`、`Secure`、`Expires` 和 `Max-Age`
  约束；不要依赖浏览器专属 Cookie 行为或公共后缀策略。
- URL options 可使用 `method`、`headers`、`body`、`charset`、`retry`。
- 不依赖 `webView`、`webJs`、`js`、登录脚本、动态签名或加密算法。

### 规则

- 首选 CSS 选择器。
- 支持文本、属性、`html`、`innerhtml`、`outerhtml` getter。
- 支持 JSONPath 子集：字段、数组索引、通配、简单递归字段、union、正向 slice。
- 支持简单 XPath 子集：路径、属性等值、class/id、`contains(@class,'x')`、末尾取属性 / 文本 / HTML。
- 支持有限正则：常见捕获、`\d`、`\s`、`\w`、`\n`、`\r`、`\t`、`[\s\S]`。
- 不依赖环视、正则分支 `|`、`\b`、`\p{}`、复杂 XPath 谓词、轴选择、位置函数。
- 支持 `&&` 顺序处理、`||` 兜底、`%%` 多列表交错合并。
- 支持 `规则##pattern##replacement` 清洗；replacement 可用 `%1` / `%2` 或 `$1` / `$2`。
- 支持 `@put:{...}` 与 `@get:{key}` 做简单变量传递。

## 编写步骤

### 1. 取证站点

- 确认搜索页、详情页、目录页、正文页的真实 URL。
- 记录最终跳转 URL、请求方法、请求参数、必要 header、响应编码和分页规律。
- 用真实响应写规则，不用浏览器渲染后的 DOM 猜规则。
- 遇到必须 JS 渲染、WebView、登录脚本、动态签名的站点，标记为当前不可支持。
- GBK / GB2312 / GB18030 站点只在 URL options 写 `charset`，不要在字段规则里手工转码。

### 2. 写 URL

- 搜索关键词用 `{{key}}`。
- 页码用 `{{page}}`、`{{page+1}}`、`{{page-1}}`。
- `{{...}}` 在插件中不是任意 JavaScript，只允许 `key`、`page`、
  `page+N`、`page-N`。
- GET 示例：

  ```text
  https://site/search?q={{key}}&page={{page}}
  ```

- POST form 示例：

  ```text
  https://site/search,{\"method\":\"POST\",\"headers\":{\"Content-Type\":\"application/x-www-form-urlencoded\"},\"body\":\"q={{key}}&page={{page}}\",\"charset\":\"gb18030\"}
  ```

- POST JSON 要显式写 `Content-Type`：

  ```text
  https://site/api,{\"method\":\"POST\",\"headers\":{\"Content-Type\":\"application/json; charset=UTF-8\"},\"body\":{\"q\":\"{{key}}\",\"page\":\"{{page}}\"}}
  ```

- `exploreUrl` 使用 `标题::URL`；多个入口用 `&&` 或换行分隔。
- 分页固定两种形态时可用 `<第一页,后续页>`：

  ```text
  https://site/list/<index.html,index_{{page}}.html>
  ```

- URL options 必须是合法 JSON；字符串中的双引号要转义。
- 不写 `@js:`、`<js>`、`webView`、`webJs`、非 `key/page/page+N/page-N` 的 `{{...}}`。

### 3. 写 header、body、Cookie

- 顶层 `header` 作为默认 header；单个 URL 的 `headers` 用于补充或覆盖当前请求。
- 不要同时写 `content-type` 和 `Content-Type`。
- 能不写 `Cookie` 就不写；优先依赖响应 `Set-Cookie`。
- 必须手工写 Cookie 时，只写必要键值：

  ```json
  "{\"Cookie\":\"a=1; b=2\"}"
  ```

- 普通 form body 不要手工 URL 编码。
- JSON / XML body 不要写成 form。
- `charset` 描述请求参数编码和响应解码。

### 4. 写搜索或发现列表

- `ruleSearch.bookList` / `ruleExplore.bookList` 选中重复的单本书节点，不选整个列表容器。
- 列表字段相对单本书节点解析。
- 先让 `bookList` 数量正确，再补字段。
- `name` 和 `bookUrl` 是核心字段；`bookUrl` 为空通常会导致详情页错误。
- `intro` 只写简介。
- `author`、`updateTime`、`wordCount`、`kind`、`lastChapter` 只写对应元数据。
- URL 字段使用 `a@href`、`img@src` 等 getter；相对地址会转绝对地址。

### 5. 写详情页

- `ruleBookInfo` 优先补全列表缺失字段。
- `intro` 只返回纯文本简介正文，不混入作者、更新时间、字数、最新章节。
- 不要为了简介使用 `@html`。
- `tocUrl` 指向目录页；如果目录就在详情页，可留空。
- `init` 只用于先裁剪详情页局部区域，不用于模拟运行逻辑。

### 6. 写目录

- `ruleToc.chapterList` 选中章节项。
- 章节名写 `chapterName`，章节链接写 `chapterUrl`。
- 卷标题用 `isVolume`。
- 付费 / 锁章用 `isVip`。
- 分页目录写 `nextTocUrl`，不要把下一页 URL 混成章节。
- 章节倒序时在 `chapterList` 前加 `-`，不要修改章节标题或 URL。

### 7. 写正文

- `ruleContent.content` 必填。
- 纯文本正文优先选择段落级节点，例如 `div.content p`、`div.content > p`、`div.content > div`。
- 多个命中节点会用换行连接。
- 不要直接用大容器抓纯文本，除非确认正文不需要段落。
- 只有正文依赖 `<br>`、图片、表格或特殊内联结构时，才使用最小范围的 `@html`、`@innerhtml` 或 `@outerhtml`。
- 分页正文写 `nextContentUrl`，不要把下一章链接误判成正文分页。
- `sourceRegex` 只用于先裁剪原始响应。
- `replaceRegex` 只用于最终正文清洗。

## 规则语法

- 默认 CSS：`div.book h3 a`
- 强制 CSS：`@CSS:div.book h3 a`
- 属性：`a@href`、`img@src`
- HTML：`div.intro@html`、`div.content@outerhtml`
- JSONPath：
  - `$.data.book.name`
  - `$['data']['book']`
  - `$.items[0]`
  - `$.items[-1]`
  - `$.items[*].name`
  - `$..name`
  - `$.items[0,2].name`
  - `$.meta['name','author']`
  - `$.items[0:10].name`
  - `$.items[:10].name`
  - `$.items[0:10:2].name`
- XPath：
  - `//div[@class='book']//a/@href`
  - `//div[@id='main']/text()`
  - `//div[contains(@class,'book')]/text()`
- 顺序处理：`规则1&&规则2`
- 兜底：`规则1||规则2`
- 交错合并：`规则1%%规则2`
- 替换：`规则##pattern##replacement`
- 正则列表裁剪：`:<区域规则>&&<条目规则>`
- 捕获结果：`$[0]` 是完整匹配，`$[1]`、`$[2]` 是捕获组。
- 变量：
  - 写入：`@put:{"key":"规则"}`
  - 读取：`@get:{key}`

## 验证

1. 检查 JSON：

   ```bash
   jq empty plugins/novel.koplugin/source/<name>.json
   ```

2. 验证完整链路：搜索或发现 -> 详情 -> 目录 -> 正文。
3. 检查每段链路的请求 URL、最终 URL、状态码、响应 charset、解析数量、`unsupported`。
4. 检查中文关键词、GBK / GB18030、POST form 的编码是否正确。
5. 需要 Cookie 的站点，检查首次请求、`Set-Cookie`、后续同源请求。
6. 声明分页的地方必须验证分页：搜索 / 发现分页、目录分页、正文分页。
7. 失败排查顺序：
   - JSON 语法
   - 请求方法 / 参数
   - URL 编码
   - header / Cookie
   - charset
   - 最终跳转 URL
   - 列表范围
   - 字段 getter
   - 正则 / JSONPath / XPath 兼容性
   - unsupported 能力

## 完成标准

- JSON 合法。
- 搜索或发现能返回稳定书籍列表。
- 字段语义正确；能稳定提取的字段已尽量补齐。
- 详情页能补齐列表缺失信息。
- 目录章节数量、顺序、URL 正确。
- 正文非空，段落可读。
- HTML 正文只在确有结构需求时使用，且选择范围足够小。
- 请求参数、header、body、charset、Cookie 都有取证依据。
- 没有未解释的 `unsupported`。
- 不能支持的 JS / WebView / 登录 / 动态签名路径已明确说明。
