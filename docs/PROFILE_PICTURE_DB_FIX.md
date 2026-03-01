# Profile Picture: DB Not Updating — Backend Fix

**Problem:** Profile picture file is saved locally (and to cloud) but the value is not persisted in the database.

**Likely causes:**
1. Mongoose not detecting the change on the document (e.g. field type or how the doc was loaded).
2. Save error is not logged, so failures are silent.
3. Relying on in-memory document `.save()` instead of an explicit update.

---

## Fix 1: Force Mongoose to see the change + log errors

Before `curr_user.save()`, call `markModified` so Mongoose includes `profile_picture` in the update, and log the save error:

```javascript
curr_user.profile_picture = picPath;
app.locals.profile_picture = picPath;
// Force Mongoose to persist this field (needed for Mixed or if change not detected)
curr_user.markModified('profile_picture');

await fileUpload2Cloud(serverPath, picPath);

curr_user.save((err) => {
  if (err) {
    console.error('Profile picture save error:', err);
    res.json({ path: null, result: 'FAIL' });
    return;
  }
  res.json({ path: picPath, result: 'OK' });
});
```

---

## Fix 2 (recommended): Use `findByIdAndUpdate` so DB is updated explicitly

Avoid relying on the in-memory document’s change tracking. After the file is moved and uploaded to cloud, update the DB directly:

```javascript
// ... after fileUpload2Cloud(serverPath, picPath) ...

User.findByIdAndUpdate(
  req.params.user_id,
  { profile_picture: picPath },
  { new: true },
  (err, updatedUser) => {
    if (err) {
      console.error('Profile picture DB update error:', err);
      return res.json({ path: null, result: 'FAIL' });
    }
    if (!updatedUser) {
      return res.status(404).json({ path: null, result: 'FAIL' });
    }
    app.locals.profile_picture = picPath;
    res.json({ path: picPath, result: 'OK' });
  }
);
```

Then you can remove the earlier `curr_user.profile_picture = picPath` and `curr_user.save()` (and the `curr_user.markModified` if you only use Fix 2).

---

## Ensure `profile_picture` is in the User schema

In your User model, the field must be defined, e.g.:

```javascript
const userSchema = new mongoose.Schema({
  // ...
  profile_picture: { type: String, default: null },
  // ...
});
```

If it’s missing, Mongoose will ignore it when saving the document.

---

## Full route example (using Fix 2)

```javascript
app.post('/profile/:user_id/file_upload', (req, res) => {
  const { user_id } = req.params;
  console.log(`file upload: user_id: ${user_id}`);

  if (Object.keys(req.files).length === 0) {
    return res.status(400).send('No files were uploaded.');
  }

  const sampleFile = req.files.file_name;
  const picPath = `/public/user_resources/pictures/profile_pictures/${user_id}_profile_${sampleFile.name}`;

  User.findById(user_id, (err, curr_user) => {
    if (err || !curr_user) {
      console.error('User lookup error:', err);
      return res.status(404).send('User not found');
    }

    sampleFile.mv(serverPath + picPath, async (err) => {
      if (err) {
        console.warn(`upload failure. error=${err}`);
        return res.status(500).send(err);
      }

      if (curr_user.profile_picture) {
        fileDeleteFromCloud(curr_user.profile_picture);
      }

      await fileUpload2Cloud(serverPath, picPath);

      User.findByIdAndUpdate(
        user_id,
        { profile_picture: picPath },
        { new: true },
        (updateErr) => {
          if (updateErr) {
            console.error('Profile picture DB update error:', updateErr);
            return res.json({ path: null, result: 'FAIL' });
          }
          app.locals.profile_picture = picPath;
          res.json({ path: picPath, result: 'OK' });
        }
      );
    });
  });
});
```

Apply this in your backend repo (where `app.js` and the User model live). After deploying, profile picture updates should persist in the DB.
