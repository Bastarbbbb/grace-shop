# Grace Shop

Boutique de mode et de bijoux à Lomé : robes en wax, boubous, bijoux et accessoires, avec paiement T-Money ou à la livraison et commandes envoyées sur WhatsApp.

C'est une application web installable (PWA) : un seul code pour le site, le téléphone Android, l'iPhone et l'ordinateur.

## Contenu du dépôt

| Fichier | Rôle |
|---|---|
| `index.html` | Toute l'application : vitrines 3D, catalogue, panier, commande, espace vendeur |
| `data/shop.json` | Le catalogue (articles, prix, catégories, réglages de la boutique) |
| `manifest.webmanifest` | Nom, icônes et couleurs quand l'application est installée |
| `sw.js` | Permet d'ouvrir la boutique même avec une connexion faible |
| `icons/` | Icônes de l'application (Android, iPhone, ordinateur) |

## Modifier le catalogue

Ouvrez `data/shop.json` sur GitHub, cliquez sur le crayon, changez un nom ou un prix, puis cliquez sur **Commit changes**. Le site se met à jour en une à deux minutes.

## Mettre le site en ligne (GitHub Pages)

1. Dans le dépôt : **Settings → Pages**.
2. Source : **Deploy from a branch**, branche `main`, dossier `/ (root)`.
3. L'adresse du site apparaît en haut de la page (par exemple `https://grace-shop.github.io/`).

GitHub Pages est gratuit pour un dépôt **public**. Pour un dépôt privé, il faut un abonnement GitHub payant.

## Installer sur téléphone dès maintenant (gratuit)

- **Android (Chrome)** : ouvrir le site → menu ⋮ → **Installer l'application**.
- **iPhone (Safari)** : ouvrir le site → bouton Partager → **Sur l'écran d'accueil**.

L'icône Grace Shop apparaît alors comme une vraie application.

## Publier sur le Play Store (Android)

1. Créer un compte **Google Play Console** (frais unique de 25 $).
2. Aller sur **pwabuilder.com**, coller l'adresse du site, choisir **Android**, télécharger le paquet.
3. Envoyer le fichier `.aab` dans la Play Console, remplir la fiche (photos, description), soumettre.
4. Mettre le fichier `assetlinks.json` fourni par PWABuilder dans `.well-known/` de ce dépôt.

## Publier sur l'App Store (iPhone)

1. Créer un compte **Apple Developer** (99 $ par an).
2. Sur **pwabuilder.com**, choisir **iOS** et télécharger le projet.
3. Le compiler avec **Xcode sur un Mac**, puis l'envoyer à Apple.

Apple refuse souvent les applications qui ne sont qu'un site web. Pour être acceptée, l'application devra proposer plus que le site, par exemple des notifications ou un compte client.

## Paiement automatique T-Money (PayGate Global)

1. Ouvrir un **compte marchand** sur paygateglobal.com et attendre la validation.
2. Récupérer la **clé API** dans le tableau de bord PayGate.
3. **Ne jamais mettre cette clé dans ce dépôt** : tout le monde pourrait la lire.
4. La clé doit être placée dans un petit serveur (par exemple une fonction Cloudflare Workers ou Supabase) qui crée le paiement et reçoit la confirmation de PayGate. C'est l'étape suivante du projet.

## Limite actuelle

L'espace vendeur (publier, modifier, ajouter des photos depuis l'application) fonctionne dans la version hébergée sur Claude. Sur GitHub Pages, le catalogue se modifie dans `data/shop.json`. Pour publier depuis le téléphone sur la version en ligne, il faudra brancher une base de données (Supabase ou Firebase).

## Comptes, espace propriétaire et commandes (Supabase)

1. Créez un projet gratuit sur https://supabase.com.
2. Dans **SQL Editor**, collez le contenu de `supabase/schema.sql` (en remplaçant `__OWNER_EMAIL__` par l'email de la propriétaire), puis **Run**.
3. Dans **Authentication → Sign In / Providers → Email**, désactivez **Confirm email** (les clientes s'inscrivent avec leur numéro).
4. Dans **Authentication → URL Configuration**, mettez `https://grace-shop.github.io` comme **Site URL**.
5. Mettez la **Project URL** et la clé **anon public** dans `config.js`.

La propriétaire crée ensuite son compte sur le site (bouton « Se connecter » → « Nouveau compte ») avec cet email : elle obtient l'espace vendeur et le tableau des commandes.
