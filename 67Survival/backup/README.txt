Backups of the scripts that the BESTIARY update (enemies by difficulty, ability visuals, premium
abilities) replaces. They are plain text (StringValue) so they never run and are never required.
Rojo maps them to ServerStorage/_Backup_Enemies and ServerStorage/_Backup_Scripts.

State before the update: git commit 72e3ced ("Enemies by tier: ..."). To roll back, either
`git checkout 72e3ced -- 67Survival/src` or copy a StringValue's text back into its script.
