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
    File
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

import de.dlkw.ccrypto.svc {
    sha256
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

shared String fetchColumnInfo(String columnName) {
    String columnInfo = getColumn(columnName);
    Path path = parsePath("``columnName``_info.json");
    writeFile(columnInfo, path);
    return columnInfo;
}

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

shared {Uri*} titleImagesUrls(JsonArray posts) {
    return { for (post in posts)
            if (is JsonObject post, exists url = titleImageUrl(post))
                url };
}

shared ArrayList<Process> fetchTitleImages(JsonArray posts) {
    {Uri*} urls = titleImagesUrls(posts);
    value tasks = ArrayList<Process>();
    for (url in urls) {
        tasks.add(fetchFile(url));
    }
    return tasks;
}

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

shared String content(JsonObject post) {
    if (is String postContent = post["content"], !postContent.empty) {
        return postContent;
    } else {
        throw KeyNotFound("content");
    }
}

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

shared ArrayList<Process> fetchContentImages(JsonArray posts) {
    value tasks = ArrayList<Process>();
    for (content in contents(posts)) {
        for (imagePath in contentImage(content)) {
            tasks.add(fetchFile(urlify(imagePath)));
        }
    }
    return tasks;
}

void fetchColumnPosts(String columnName) {
    String columnInfo = fetchColumnInfo(columnName);
    value [count, avatar, creatorAvatar] = parseColumnInfo(columnInfo);
    value tasks = ArrayList<Process>();
    tasks.addAll(fetchAvatarFiles(avatar, creatorAvatar));
    
    String? posts = fetchPosts(count, columnName);
    if (exists posts, is JsonArray postsJson = parseJson(posts)) {
        fetchComments(postsJson);
        tasks.addAll(fetchTitleImages(postsJson));
        tasks.addAll(fetchContentImages(postsJson));
    }
}

[Integer?, Uri?, Uri?] parseColumnInfo(String columnInfo) {
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

Process fetchFile(Uri url) {
    Process process = createProcess {
        command = "wget";
        arguments = ["-c", url.string]; // --continue
    };
    return process;
}

ArrayList<Process> fetchAvatarFiles(Uri? avatar, Uri? creatorAvatar) {
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
void writeFile(String content, Path filePath) {
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

String? fetchPosts(Integer? count, String columnName) {
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
Uri column(String name) {
    return parseUri("``apiRoot``/columns/name");
}
Uri posts(String name, Integer limit = 10) {
    if (limit > 0) {
        return parseUri("``column(name)``/posts?limit=``limit``");
    } else {
        throw InvalidTypeException("`limit` > 0");
    }
}
Uri comments(Integer slug) {
    return parseUri("``apiRoot``/posts/``slug``/comments");
}

"Given a Uri, get Response contents, following one direct."
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
        throw Exception("Got ``r.status``.");
    }
}

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

class KeyNotFound(String key) extends Exception("`key` not found.") {}

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

shared Integer slug(JsonObject post) {
    if (is Integer slug = post["slug"]) {
        return slug;
    } else {
        throw InvalidTypeException("No slug field in post!");
    }
}

shared {Integer*} slugs(JsonArray posts) {
    return { for (post in posts) if (is JsonObject post) slug(post) };
}

shared String? getComments(Integer slug) {
    return getContent(comments(slug));
}
