import os
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, Session
from settings import settings
from db_models import Base

class DatabaseManager:
    def __init__(self):
        pass

    def _get_engine(self, db_name: str):
        # Always use current settings.USERS_DIR to pick up overrides
        users_dir = settings.USERS_DIR
        if not os.path.exists(users_dir):
            try:
                os.makedirs(users_dir, exist_ok=True)
            except Exception:
                pass

        path = os.path.join(users_dir, db_name)
        url = f"sqlite:///{path}"
        return create_engine(url, connect_args={"check_same_thread": False})

    def get_session(self, engine):
        SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
        return SessionLocal()

    def get_global_users_engine(self):
        return self._get_engine("global_users.db")

    def get_uploads_engine(self):
        return self._get_engine("uploads.db")

    def get_user_data_engine(self, username: str):
        return self._get_engine(f"{username}_data.db")

    def get_user_stats_engine(self, username: str):
        return self._get_engine(f"{username}_stats.db")

    def init_global_dbs(self):
        # Create tables for global DBs
        from db_models import GlobalUser, Upload
        Base.metadata.create_all(self.get_global_users_engine(), tables=[GlobalUser.__table__])
        Base.metadata.create_all(self.get_uploads_engine(), tables=[Upload.__table__])

    def init_user_dbs(self, username: str):
        # Create tables for specific user DBs
        from db_models import UserData, Favorite, SuggestLess, Hidden, PlaySession, PlayEvent, Playlist, PlaylistSong
        
        # 1. User Data DB
        e_data = self.get_user_data_engine(username)
        Base.metadata.create_all(e_data, tables=[
            UserData.__table__, 
            Favorite.__table__, 
            SuggestLess.__table__, 
            Hidden.__table__,
            Playlist.__table__,
            PlaylistSong.__table__
        ])
        
        # 2. Stats DB
        e_stats = self.get_user_stats_engine(username)
        Base.metadata.create_all(e_stats, tables=[PlaySession.__table__, PlayEvent.__table__])

db_manager = DatabaseManager()