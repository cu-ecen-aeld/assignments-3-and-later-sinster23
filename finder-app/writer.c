#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h> 
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <syslog.h>

int main(int argc, char *argv[]) {
    openlog("writer", LOG_PID | LOG_CONS, LOG_USER);
    if (argc != 3) {
        syslog(LOG_ERR, "Usage: %s <file> <string>\n", argv[0]);
        closelog();
        return 1;
    }

    const char *filePath = argv[1];
    const char *text = argv[2];

    int fd = open(filePath, O_WRONLY | O_CREAT | O_TRUNC, 0777);
    if (fd == -1) {
        syslog(LOG_ERR, "Cannot open file\n");
        closelog();
        return 1;
    }

    syslog(LOG_DEBUG, "Writing %s to %s", text, filePath);
    ssize_t written =  write(fd, text, strlen(text));
    if (written == -1)
    {
        /* code */
        syslog(LOG_ERR, "Cannot write file\n");
        close(fd);
        closelog();
        return 1;
    }
    
    close(fd);
    closelog(); // Đóng kết nối
    return 0;
}
