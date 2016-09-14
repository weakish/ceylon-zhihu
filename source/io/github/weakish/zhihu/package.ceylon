"""Readonly API client of zhuanlan.zhihu.com

   Currently it supports:

   - column info
   - all posts
   - comments for post
   - comments for all posts

   zhuanlan.zhihu.com also has an endpoint of a single post, consist of

        * lastestLikers: I do not know a way to get all likes
        `/api/posts/SLUG/{like,likes}` both get 404.
        * previous and next post without latestetLikes
        * Note there is no comments.

   So except for latest likeers, it does not provide more information than `posts`.
   This API endpoint is not implemented.
   Instead, an API to (all) likes may be implemented in future.

   Functions to fetch avatar images, title images,
   and images in post content are also provided.
"""
shared package io.github.weakish.zhihu;
