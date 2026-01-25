import os
import logging
from sqlalchemy import create_engine, text, inspect
from sqlalchemy.orm import sessionmaker, Session
from sqlalchemy.schema import CreateTable
from settings import settings
from db_models import Base

logger = logging.getLogger("uvicorn.error")

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

    def _ensure_table_exists(self, engine, table_model):
        """Ensure a table exists, create if it doesn't."""
        inspector = inspect(engine)
        table_name = table_model.__tablename__
        
        if table_name not in inspector.get_table_names():
            logger.info(f"Creating table: {table_name}")
            table_model.__table__.create(engine, checkfirst=True)
            return True
        return False

    def _ensure_columns_exist(self, engine, table_model):
        """Ensure all columns in the model exist in the database table."""
        inspector = inspect(engine)
        table_name = table_model.__tablename__
        
        if table_name not in inspector.get_table_names():
            return False  # Table doesn't exist, will be created separately
        
        existing_columns = {col['name'] for col in inspector.get_columns(table_name)}
        model_columns = {col.name for col in table_model.__table__.columns}
        
        missing_columns = model_columns - existing_columns
        
        if missing_columns:
            logger.info(f"Adding missing columns to {table_name}: {missing_columns}")
            with engine.connect() as conn:
                for column_name in missing_columns:
                    column = table_model.__table__.columns[column_name]
                    # Generate ALTER TABLE statement manually
                    column_type = str(column.type)
                    alter_sql = f"ALTER TABLE {table_name} ADD COLUMN {column_name} {column_type}"
                    
                    # Handle nullable and default values
                    if not column.nullable and column.default is None:
                        # For NOT NULL columns without default, allow NULL initially then update
                        alter_sql += " NULL"
                    elif column.nullable:
                        alter_sql += " NULL"
                    else:
                        alter_sql += " NOT NULL"
                    
                    # Add default value if specified
                    if column.default is not None:
                        if hasattr(column.default, 'arg'):
                            default_val = column.default.arg
                        else:
                            default_val = column.default
                        alter_sql += f" DEFAULT {default_val}"
                    
                    conn.execute(text(alter_sql))
                conn.commit()
            return True
        return False

    def _migrate_table(self, engine, table_model):
        """Complete table migration: ensure table exists and has all columns."""
        table_created = self._ensure_table_exists(engine, table_model)
        columns_added = self._ensure_columns_exist(engine, table_model)
        return table_created or columns_added

    def init_global_dbs(self):
        """Initialize and migrate global databases."""
        logger.info("Checking global databases for migrations...")
        
        # Import models
        from db_models import GlobalUser, Upload
        
        # Migrate global users DB
        global_users_engine = self.get_global_users_engine()
        self._migrate_table(global_users_engine, GlobalUser)
        
        # Migrate uploads DB
        uploads_engine = self.get_uploads_engine()
        self._migrate_table(uploads_engine, Upload)
        
        logger.info("Global database migrations completed")

    def init_user_dbs(self, username: str):
        """Initialize and migrate user-specific databases."""
        logger.info(f"Checking user databases for {username}...")
        
        # Import models
        from db_models import UserData, Favorite, SuggestLess, Hidden, PlaySession, PlayEvent, Playlist, PlaylistSong
        
        # 1. User Data DB migrations
        e_data = self.get_user_data_engine(username)
        self._migrate_table(e_data, UserData)
        self._migrate_table(e_data, Favorite)
        self._migrate_table(e_data, SuggestLess)
        self._migrate_table(e_data, Hidden)
        self._migrate_table(e_data, Playlist)
        self._migrate_table(e_data, PlaylistSong)
        
        # 2. Stats DB migrations
        e_stats = self.get_user_stats_engine(username)
        self._migrate_table(e_stats, PlaySession)
        self._migrate_table(e_stats, PlayEvent)
        
        logger.info(f"User database migrations completed for {username}")

    def _ensure_uploads_columns(self):
        """Legacy method for uploads column migration - kept for compatibility."""
        try:
            engine = self.get_uploads_engine()
            with engine.connect() as conn:
                # Check columns
                result = conn.execute(text("PRAGMA table_info(upload)")).fetchall()
                existing_cols = {r[1] for r in result}
                
                if "album" not in existing_cols:
                    conn.execute(text("ALTER TABLE upload ADD COLUMN album TEXT"))
                    conn.commit()
                    logger.info("Migration: Added 'album' column to upload table")
        except Exception as e:
            logger.error(f"Migration error for uploads: {e}")

    def _ensure_user_data_columns(self, username: str):
        """Legacy method for user data column migration - kept for compatibility."""
        path = os.path.join(settings.USERS_DIR, f"{username}_data.db")
        if not os.path.exists(path):
            return

        try:
            engine = self.get_user_data_engine(username)
            with engine.connect() as conn:
                # Check if userdata table exists first
                table_check = conn.execute(text("SELECT name FROM sqlite_master WHERE type='table' AND name='userdata'")).fetchone()
                if not table_check:
                    return

                # Check columns
                result = conn.execute(text("PRAGMA table_info(userdata)")).fetchall()
                existing_cols = {r[1] for r in result}
                
                if "theme_mode" not in existing_cols:
                    conn.execute(text("ALTER TABLE userdata ADD COLUMN theme_mode TEXT"))
                if "sync_theme" not in existing_cols:
                    conn.execute(text("ALTER TABLE userdata ADD COLUMN sync_theme INTEGER DEFAULT 0"))
                conn.commit()
                logger.info(f"Migration: Added theme columns to userdata table for {username}")
        except Exception as e:
            logger.error(f"Migration error for {username}: {e}")

    def run_full_migration(self):
        """Run complete migration for all databases."""
        logger.info("Starting full database migration...")
        
        try:
            # Migrate global databases
            self.init_global_dbs()
            
            # Migrate all existing user databases
            if os.path.exists(settings.USERS_DIR):
                for filename in os.listdir(settings.USERS_DIR):
                    if filename.endswith("_data.db"):
                        username = filename.replace("_data.db", "")
                        self.init_user_dbs(username)
            
            logger.info("Full database migration completed successfully")
        except Exception as e:
            logger.error(f"Full migration failed: {e}")
            raise

db_manager = DatabaseManager()