# Publishing checklist

The README's `brew tap` instructions only become true after all of these.
Do them in order — the formula's `sha256` depends on the tag existing.

## 1. Push the code repo

```bash
gh repo create aintyourcupoftea/safari-download-manager --public --source=. --push
# or: git remote add origin git@github.com:aintyourcupoftea/safari-download-manager.git
#     git push -u origin main
```

## 2. Tag a release

```bash
git tag v0.1.0
git push origin v0.1.0
```

## 3. Get the tarball hash

```bash
curl -sL https://github.com/aintyourcupoftea/safari-download-manager/archive/refs/tags/v0.1.0.tar.gz \
  | shasum -a 256
```

Put that value into `dist/Formula/safari-download-manager.rb`, replacing
`REPLACE_WITH_RELEASE_SHA256`.

## 4. Create the tap repo

A Homebrew tap must be a **separate** repo named `homebrew-<tapname>`:

```bash
mkdir homebrew-tap && cd homebrew-tap && git init
mkdir Formula
cp ../safari-download-manager/dist/Formula/safari-download-manager.rb Formula/
git add -A && git commit -m "safari-download-manager 0.1.0"
gh repo create aintyourcupoftea/homebrew-tap --public --source=. --push
```

## 5. Verify end to end

```bash
brew untap aintyourcupoftea/tap 2>/dev/null
brew tap aintyourcupoftea/tap
brew install safari-download-manager
brew test safari-download-manager
sdm setup
```

## 6. Bumping versions later

Re-tag, recompute the sha256, update the formula in the tap repo. Homebrew
picks it up on `brew update`.
