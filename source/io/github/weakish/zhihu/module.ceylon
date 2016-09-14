"""A client to zhihu.com API.

   Currently it supports readonly APIs of zhuanlan.zhihu.com.

   For example, column(blog) info and posts count of `https://zhuanlan.zhihu.com/wooyun`:

   ```ceylon
   String columnName = "wooyun";
   String columnInfo = getColumn(columnName);
   if (is JsonObject column = parseJson(columnInfo)) {
       print(postsCount(column));
   }
   ```

   Get all posts from a column (assuming it has 42 posts):

   ```ceylon
   String posts = getPosts(columnName, 42);
   ```

   There are also some `fetch*` functions as usage examples.

   This module can also be used as a command line tool to backup a column:

       java -jar zhihu.jar COLUMN_NAME

   It will download column info, all posts with comments as json files.
   Also, it will fetch avatar, title and in post images.

   Currently it uses a naive strategy to deal with name collosion:
   rename it with SHA256 postfix.

   Possible clauses of name collosion:

   - images in posts have somee file name, e.g.

       * `http://hostA/same.jpg` and `http://hostB/same.jpg`
       * `http://same/dirA/same.jpg` and `http://same/dirB/same.jpg`

   - rerun zhihu.jar

   Also, incremental backup with reruning is not implemented yet.
   """


native ("jvm") module io.github.weakish.zhihu "0.0.0" {
    shared import ceylon.json "1.2.2";
    shared import ceylon.net "1.2.2";
    shared import ceylon.collection "1.2.2";
    import ceylon.file "1.2.2";
    shared import ceylon.process "1.2.2";
    import ceylon.regex "1.2.2";
    import ceylon.random "1.2.2";
    import ceylon.time "1.2.2";
    import ceylon.logging "1.2.2";
    import ceylon.test "1.2.2";
    import de.dlkw.ccrypto.svc "0.0.2";
}
