"""Top-level package for CentOS Image Builder for the AWS MP."""
# centos-2-awsmp/__init__.py

__app_name__ = "centos-2-awsmp"
__version__ = "0.1.2"

(
    SUCCESS,
    DIR_ERROR,
    FILE_ERROR,
    DB_READ_ERROR,
    DB_WRITE_ERROR,
    JSON_ERROR,
    ID_ERROR,
    ) = range(7)

ERRORS = {
    DIR_ERROR: "config directory error",
    FILE_ERROR: "config file error",
    DB_READ_ERROR: "database read error",
    DB_WRITE_ERROR: "database write error",
    ID_ERROR: "product id error",
    }
