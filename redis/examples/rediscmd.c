/**
 * rediscmd.c
 *   connect to redis cluster and exec some redis commands.
 *   use hiredis c api only !
 *
 * hiredis_ssl:
 *   https://blog.51cto.com/u_16213405/7654873
 * 
 * @author: master@mapaware.top
 *
 * @version: 0.1.0
 * @create: 2024-09-18
 * @update: 2024-09-18
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

#include <hiredis/hiredis.h>
#include <hiredis/async.h>

int main(int argc, char *argv[])
{
    redisContext *ctx;
    redisReply *reply;

    printf("rediscmd start running ...\n");

    // 1.5 seconds
    struct timeval timeout = { 1, 500000 };

    ctx = redisConnectWithTimeout("hacl-node1", 6379, timeout);
    if (! ctx) {
        printf("rediscmd exit with error.\n");
        exit(-1);
    }

    if (ctx->err) {
        printf("redis connection error: %s\n", ctx->errstr);
        redisFree(ctx);
        printf("rediscmd exit with error.\n");
        exit(-1);
    }

    reply = (redisReply *) redisCommand(ctx, "AUTH test");
    printf("redis reply: %s\n", reply->str);
    freeReplyObject(reply);

    reply = (redisReply *) redisCommand(ctx, "GET name");
    printf("redis reply: %s\n", reply->str);
    freeReplyObject(reply);

    redisFree(ctx);
    printf("rediscmd exit with success.\n");    
}