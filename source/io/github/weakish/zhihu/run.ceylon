import ceylon.buffer.base {
    base16String
}
import ceylon.buffer.charset {
    utf8
}
import ceylon.collection {
    ArrayList
}
import ceylon.file {
    Path,
    parsePath,
    Nil,
    File,
    current,
    createFileIfNil,
    Directory,
    Link
}
import ceylon.json {
    JsonObject=Object,
    JsonArray=Array,
    parseJson=parse,
    InvalidTypeException,
    Value
}
import ceylon.logging {
    addLogWriter,
    writeSimpleLog,
    Logger,
    logger
}
import ceylon.net.http {
    Header
}
import ceylon.net.http.client {
    Response
}
import ceylon.net.uri {
    Uri,
    parseUri=parse
}
import ceylon.process {
    Process,
    createProcess
}
import ceylon.random {
    DefaultRandom
}
import ceylon.regex {
    Regex,
    regex,
    MatchResult
}
import ceylon.time {
    now
}

import de.dlkw.ccrypto.svc {
    sha256
}
import ceylon.test {
    assertEquals,
    test
}

"Run the module `io.github.weakish.zhihu`."
shared void run() {
    addLogWriter(writeSimpleLog);
    if (exists columnName = process.arguments.first) {
        try {
            fetchColumnPosts(columnName);
        } catch (e) {
            process.writeErrorLine(e.message);
        }
    } else {
        process.writeErrorLine("Usage: zhihu COLUMN_NAME");
        process.writeErrorLine("Get COLUNM_NAME: https://zhuanlan.zhihu.com/{COLUMN_NAME}");
        process.exit(ex_usage);
    }
}

Integer ex_usage = 64;

Logger log = logger(`module io.github.weakish.zhihu`);

"Returns column info json string."
shared String fetchColumnInfo(String columnName) {
    String columnInfo = getColumn(columnName);
    Path path = parsePath("``columnName``_info.json");
    writeFile(columnInfo, path);
    return columnInfo;
}

"Fetch comments json files, named `POST_SLUG_comments."
shared void fetchComments(JsonArray posts) {
    for (slug in slugs(posts)) {
        String? comment = getComments(slug);
        if (exists comment, parseJson(comment) is JsonArray) {
            Path path = parsePath("``slug``_comments");
            writeFile(comment, path);
        } else {
            log.error("Unable to fetch or parse comments of post ``slug``");
        }
    }
}

"`titleImage` may be an empty string (\"\")."
shared Uri? titleImageUrl(JsonObject post) {
    if (is String titleImage = post["titleImage"], !titleImage.empty) {
        return parseUri(titleImage);
    } else {
        return null;
    }
}

"Skip posts which can not be parsed as JsonObject, or does not contain title Image."
shared {Uri*} titleImagesUrls(JsonArray posts) {
    return { for (post in posts)
            if (is JsonObject post, exists url = titleImageUrl(post))
                url };
}

"task pool"
shared alias Tasks => ArrayList<Process>;

"Fetch title images, non blocking."
shared Tasks fetchTitleImages(JsonArray posts) {
    {Uri*} urls = titleImagesUrls(posts);
    Tasks tasks = ArrayList<Process>();
    for (url in urls) {
        tasks.add(fetchFile(url));
    }
    return tasks;
}

"Parse post content for image urls.
 Also supports special syntax of zhihu hosted images."
shared {String*} contentImage(String content) {
    Regex regexp = regex {
        expression = """<img src=\"([^"]+)"""";
        ignoreCase = true;
    };
    MatchResult[] matches = regexp.findAll(content);
    return { for (match in matches)
            if (nonempty imagePathMatch = match.groups)
                imagePathMatch.first
    };
}

"Extract post content."
throws(`class KeyNotFound`)
shared String content(JsonObject post) {
    if (is String postContent = post["content"], !postContent.empty) {
        return postContent;
    } else {
        throw KeyNotFound("content");
    }
}

"Map content(post) over posts."
shared {String*} contents(JsonArray posts) {
    return { for (post in posts) if (is JsonObject post) content(post) };
}

"Currently zhihu uses 1-4."
Integer randomCdnNumber(Integer[] cdnNumbers = [1, 2, 3, 4]) {
    value random = DefaultRandom();
    if (nonempty cdnNumbers) {
        return random.nextElement(cdnNumbers);
    } else {
        throw Exception("cdnNumbers should not be empty.");
    }
}

"Urlify images hosted by zhihu CDN."
shared Uri urlify(String imagePath, Integer cdnNumber = randomCdnNumber()) {
    Uri absoluteUrl;
    if (imagePath.startsWith("https://"), imagePath.startsWith("http://")) {
        absoluteUrl = parseUri(imagePath);
    } else if (imagePath.startsWith("//")) { // scheme-relative url
        absoluteUrl = parseUri("https:" + imagePath);
    } else { // zhihu hosted images
        absoluteUrl = parseUri("https://pic``cdnNumber``.zhimg.com/" + imagePath);
    }
    return absoluteUrl;
}

"Like [[fetchFile]] but blocking.
 Return exit code and url."
shared [Integer, String] fetchFileSync(Uri url) {
    Process process = createProcess {
        command = "wget";
        arguments = ["-c", url.string]; // --continue
    };
    return [process.waitForExit(), url.string];
}
test void fetchNonexistFile() {
    value nonexist = "nonexist://127.0.0.1/nonexist.file";
    Uri nonexistUrl = parseUri(nonexist);
    [Integer, String] result = [1, nonexist];
    assertEquals(fetchFileSync(nonexistUrl), result);
}

"Return a list of `[exitCode, failedUrl]`.

 Content images may be hosted outside zhihu, which may cause file name collosion.
 Name collosion is simply resolved as file name already exist,
 i.e. rename with `fileName_SHA256`."
shared {[Integer, String]*} fetchContentImages(JsonArray posts) {
    value urls = ArrayList<[Integer, String]>();
    for (content in contents(posts)) {
        for (imagePath in contentImage(content)) {
            // Blocking to avoid too many parallel downloads.
            urls.add(fetchFileSync(urlify(imagePath)));
        }
    }
    value failedUrls = urls.filter((pair) => !pair.first.zero);
    return failedUrls;
}

"The entrypoint gluing all fetching functions."
void fetchColumnPosts(String columnName) {
    String columnInfo = fetchColumnInfo(columnName);
    value [count, avatar, creatorAvatar] = parseColumnInfo(columnInfo);
    variable Tasks tasks = ArrayList<Process>();
    tasks.addAll(fetchAvatarFiles(avatar, creatorAvatar));
    value failedUrls = ArrayList<[Integer, String]>();
    
    String? posts = fetchPosts(count, columnName);
    if (exists posts, is JsonArray postsJson = parseJson(posts)) {
        fetchComments(postsJson);
        tasks.addAll(fetchTitleImages(postsJson));
        failedUrls.addAll(fetchContentImages(postsJson));
    }
    variable Tasks toRetry = ArrayList<Process>();
    Tasks failedRetrying = ArrayList<Process>();
    while (!tasks.empty) {
        value [unfinished, failed] = checkTasks(tasks);
        toRetry.addAll(failed);
        tasks = unfinished;
    }
    // Retry once.
    while (!toRetry.empty) {
        value [unfinished, failed] = checkTasks(toRetry);
        failedRetrying.addAll(failed);
        toRetry = unfinished;
    }
    // Record failed tasks `exitCode,url` in `zhihu_iso8061Time.csv`.
    // Prepare log file.
    String iso8601Now = now().string;
    Path logPath = current.childPath("zhihu_``iso8601Now``.csv"); // Record all failed tasks excluding content image tasks.
    for (task in failedRetrying) {
        if (exists url = task.arguments.last, exists status = task.exitCode) {
            log.debug(() =>
                    "Failed(``status``) ``task.command`` ``task.arguments`` in ``task.path``");
            switch (logLocation = logPath.resource)
            case (is File|Nil) {
                File file = createFileIfNil(logLocation);
                try (writer = file.Appender()) {
                    writer.writeLine("``status``,``url``");
                }
            }
            case (is Directory|Link) {
                log.fatal(() =>
                        "It seems ``logPath`` is a directory! Either a bug or your system time is wrong!");
            }
        } else {
            log.fatal(task.string);
        }
    }
    // Record failed urls of referred by post content.
    for ([status, url] in failedUrls) {
        switch (logLocation = logPath.resource)
        case (is File|Nil) {
            File file = createFileIfNil(logLocation);
            try (writer = file.Appender()) {
                writer.writeLine("``status``,``url``");
            }
        }
        case (is Directory|Link) {
            log.fatal(() =>
                    "It seems ``logPath`` is a directory! Either a bug or your system time is wrong!");
        }
    }
}

"Check tasks, return a tuple of [Unfinished, Failed] tasks."
shared [Tasks, Tasks] checkTasks(Tasks tasks) {
    Tasks unfinished = ArrayList<Process>();
    Tasks failed = ArrayList<Process>();
    for (task in tasks) {
        if (is Integer status = task.exitCode) {
            if (!status.zero) {
                log.debug(() =>
                        "Done: ``task.command`` ``task.arguments`` in ``task.path``");
            } else {
                log.debug(() =>
                        "Failed(``status``) ``task.command`` ``task.arguments`` in ``task.path``");
                failed.add(task);
            }
        } else {
            unfinished.add(task);
        }
    }
    return [unfinished, failed];
}

"Parse columninfo json string for postsCount, urls of avatar and creatorAvatar."
shared [Integer?, Uri?, Uri?] parseColumnInfo(String columnInfo) {
    Integer? count;
    Uri? avatar;
    Uri? creatorAvatar;
    if (is JsonObject columnInfoJson = parseJson(columnInfo)) {
        count = postsCount(columnInfoJson);
        avatar = avatarUrl(columnInfoJson);
        if (is JsonObject creator = columnInfoJson["creator"]) {
            creatorAvatar = avatarUrl(creator);
        } else {
            creatorAvatar = null;
            log.error("Creator avatar url not found.");
        }
    } else {
        count = null;
        avatar = null;
        creatorAvatar = null;
        log.error("Failed to parse column info.");
    }
    return [count, avatar, creatorAvatar];
}

"Fetch file via wget, non blocking."
shared Process fetchFile(Uri url) {
    Process process = createProcess {
        command = "wget";
        arguments = ["-c", url.string]; // --continue
    };
    return process;
}

"Non blocking."
shared Tasks fetchAvatarFiles(Uri? avatar, Uri? creatorAvatar) {
    value tasks = ArrayList<Process>();
    if (exists avatar) {
        tasks.add(fetchFile(avatar));
    }
    if (exists creatorAvatar) {
        tasks.add(fetchFile(creatorAvatar));
    }
    return tasks;
}

"Write a String to a filePath,
 if filePath already exist, write to filePath_SHA256"
shared void writeFile(String content, Path filePath) {
    if (is Nil location = filePath.resource) {
        File file = location.createFile();
        try (writer = file.Overwriter()) {
            writer.write(content);
        }
    } else {
        log.warn(() => "`filePath already exitst");
        value digester = sha256();
        value sha256Bytes = digester.digest(utf8.encode(content));
        value sha256sum = base16String.encode(sha256Bytes);
        Path newFilePath = parsePath("``filePath``.string_``sha256sum.string``");
        if (is Nil location = newFilePath.resource) {
            File file = location.createFile();
            try (writer = file.Overwriter()) {
                writer.write(content);
            }
        } else {
            log.info(() => "``filePath`` already exist, skip writting.");
        }
    }
}

"Returns a json string and saves to `COLUMN_NAME_posts.json`."
shared String? fetchPosts(Integer? count, String columnName) {
    if (exists count, count > 0) {
        String posts = getPosts(columnName, count);
        Path path = parsePath("``columnName``_posts.json");
        writeFile(posts, path);
        return posts;
    } else {
        log.warn("``columnName`` has no posts.");
        return null;
    }
}

String apiRoot = "https://zhuanlan.zhihu.com/api";

"Return full column url."
shared Uri column(String columnName) {
    return parseUri("``apiRoot``/columns/``columnName``");
}
test void columnExample() {
    assertEquals(column("wooyun"), parseUri("https://zhuanlan.zhihu.com/api/columns/wooyun"));
}

"Return posts url."
shared Uri posts(String name, Integer limit = 10) {
    if (limit > 0) {
        return parseUri("``column(name)``/posts?limit=``limit``");
    } else {
        throw InvalidTypeException("`limit` > 0");
    }
}

"Return url of comments of a single post."
shared Uri comments(Integer slug) {
    return parseUri("``apiRoot``/posts/``slug``/comments");
}

"Given a Uri, get Response contents, following one direct.
 Throws when finally getting non 200."
throws(`class Exception`)
shared String getContent(Uri url, Boolean redirected = false) {
    Response r = url.get().execute();
    switch (status = r.status)
    case (200) { // OK
        return r.contents;
    }
    case (301 | 302 | 307 | 308) { // redirect
        if (redirected == true) {
            throw Exception("Only support one redirect!");
        }
        Header? header = r.headersByName["Location"];
        if (exists location = header) {
            String? redirectUrl = location.values.first;
            if (exists redirectUrl) {
                log.warn(() => "``r.status``: redirect to ``redirectUrl``");
                return getContent(parseUri(redirectUrl), false);
            } else {
                throw Exception("Got ``r.status`` without redirect url.");
            }
        } else {
            throw Exception("Got ``r.status`` without `Location` header.");
        }
    }
    else {
        log.error(r.string);
        throw Exception("Got ``r.status`` at ``url``.");
    }
}

"Returns JsonObject[key] else null."
shared Value getJsonValue(JsonObject json, String key) {
    if (exists result = json[key]) {
        return result;
    } else {
        return null;
    }
}

"Non ascii characters are always 16 bit encoded, e.g. `\\ud7ff`,
 even with request header `Accept-Charset: utf-8`."
shared String getColumn(String name) {
    return getContent(column(name));
}

"Parse `columnInfo` or `creator` for avatar url."
shared Uri? avatarUrl(JsonObject json) {
    if (is JsonObject avatar = getJsonValue(json, "avatar")) {
        if (is String id = avatar["id"], is String template = avatar["template"]) {
            // template example: https://pic2.zhimg.com/{id}_{size}.jpg
            // `size` is one of `l` (large), `m` (middle), `s` (small).
            // You can change `pic2` to `pic{1, 3, 4}`.
            String url = template.replace("{id}", id).replace("{size}", "l");
            return parseUri(url);
        } else {
            return null;
        }
    } else {
        return null;
    }
}

"When not satisfied by just returnning null."
shared class KeyNotFound(String key) extends Exception("`key` not found.") {}

shared Integer postsCount(JsonObject json) {
    if (exists count = getJsonValue(json, "postsCount")) {
        if (is Integer count) {
            return count;
        } else {
            throw InvalidTypeException("Not an Integer: \"count\" -> ``count``");
        }
    } else {
        throw KeyNotFound("postsCount");
    }
}

"""Get posts belong to a column, including post content, without comments.
     
      The result is an array of post entries.
      Every post entry has a post id, i.e. `Integer slug`.
      Every post also has three links:
          - `"url": "/u/SLUG"` 301 to `/p/SLUG` (html url)
          - `"comments": "/api/posts/SLUG/comments"` comments
          - `"href": "/api/posts/SLUG" to a single post consist of
              * lastestLikers: I do not know a way to get all likes
                      `/api/posts/SLUG/{like,likes}` both get 404.
              * previous post without latestetLikes
              * next post without latestLikes
              * Note there is no comments.
                  Use [[getComments]] to fetch commments."""
shared String getPosts(String name, Integer limit = 10) {
    return getContent(posts(name, limit));
}

"Zhihu uses Integer for post slug."
shared Integer slug(JsonObject post) {
    if (is Integer slug = post["slug"]) {
        return slug;
    } else {
        throw InvalidTypeException("No slug field in post!");
    }
}

"Map slug(post) over posts."
shared {Integer*} slugs(JsonArray posts) {
    return { for (post in posts) if (is JsonObject post) slug(post) };
}

"Returns comments json string of a single post."
shared String? getComments(Integer slug) {
    return getContent(comments(slug));
}
