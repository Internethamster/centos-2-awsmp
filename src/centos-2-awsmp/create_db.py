from pathlib import Path

# TODO: ingest the path from the config file
db_file_name = "machine_images.db"
def create_file(file_name: str) -> str:
    Path(db_file_name).touch
if __name__ == "__main__":
    create_file(db_file_name)
