#include <stdio.h>
#include <stdlib.h>
#include <syslog.h>

int main(int argc, char *argv[])
{
    openlog(NULL, 0, LOG_USER);

    if (argc != 3)
    {
        syslog(LOG_ERR, "Invalid number of arguments");
        return 1;
    }

    char *writefile = argv[1];
    char *writestr = argv[2];

    FILE *fp = fopen(writefile, "w");

    if (fp == NULL)
    {
        syslog(LOG_ERR, "Error opening file %s", writefile);
        return 1;
    }

    syslog(LOG_DEBUG, "Writing %s to %s", writestr, writefile);

    fprintf(fp, "%s", writestr);

    fclose(fp);
    closelog();

    return 0;
}
