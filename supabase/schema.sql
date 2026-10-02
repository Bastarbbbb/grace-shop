-- Grace Shop : base de données (Supabase). À exécuter une fois dans « SQL Editor ».
-- Ré-exécutable sans danger.

-- 1) Équipe de la boutique (propriétaire, employées) : leurs emails donnent accès à l'espace vendeur.
create table if not exists public.staff (email text primary key);
alter table public.staff enable row level security;
create or replace function public.is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.staff where lower(email) = lower(coalesce(auth.jwt() ->> 'email', '')));
$$;
drop policy if exists staff_read on public.staff;
create policy staff_read on public.staff for select using (public.is_staff());

-- 2) Catalogue et réglages de la boutique (lecture publique, écriture équipe).
create table if not exists public.shop (
  id int primary key default 1 check (id = 1),
  data jsonb not null,
  rev int not null default 0,
  updated_at timestamptz not null default now()
);
alter table public.shop enable row level security;
drop policy if exists shop_read on public.shop;
drop policy if exists shop_insert on public.shop;
drop policy if exists shop_update on public.shop;
create policy shop_read on public.shop for select using (true);
create policy shop_insert on public.shop for insert with check (public.is_staff());
create policy shop_update on public.shop for update using (public.is_staff()) with check (public.is_staff());

-- 3) Profils clientes (créés automatiquement à l'inscription).
create table if not exists public.profiles (
  id uuid primary key references auth.users on delete cascade,
  name text, phone text, favs jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
drop policy if exists prof_own on public.profiles;
drop policy if exists prof_staff on public.profiles;
create policy prof_own on public.profiles for all using (auth.uid() = id) with check (auth.uid() = id);
create policy prof_staff on public.profiles for select using (public.is_staff());

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name, phone)
  values (new.id, left(new.raw_user_meta_data ->> 'name', 120), left(new.raw_user_meta_data ->> 'phone', 30))
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- 4) Commandes : tout le monde peut en passer, la cliente voit les siennes, l'équipe voit et gère tout.
create table if not exists public.orders (
  id bigint generated always as identity primary key,
  ref text unique not null check (char_length(ref) between 4 and 20),
  created_at timestamptz not null default now(),
  user_id uuid references auth.users on delete set null default auth.uid(),
  name text not null check (char_length(name) between 1 and 120),
  phone text not null check (char_length(phone) between 6 and 30),
  mode text check (mode in ('livraison','retrait')),
  zone text check (char_length(zone) <= 120),
  area text check (char_length(area) <= 300),
  pay text check (char_length(pay) <= 60),
  items jsonb not null check (jsonb_typeof(items) = 'array' and jsonb_array_length(items) between 1 and 60),
  subtotal int, fee int, discount int,
  total int not null check (total >= 0 and total < 100000000),
  promo text check (char_length(promo) <= 30),
  status text not null default 'nouvelle' check (status in ('nouvelle','confirmée','payée','en livraison','livrée','annulée')),
  note text check (char_length(note) <= 500)
);
alter table public.orders enable row level security;
drop policy if exists ord_insert on public.orders;
drop policy if exists ord_own on public.orders;
drop policy if exists ord_staff_read on public.orders;
drop policy if exists ord_staff_upd on public.orders;
drop policy if exists ord_staff_del on public.orders;
create policy ord_insert on public.orders for insert
  with check ((user_id is null or user_id = auth.uid()) and status = 'nouvelle');
create policy ord_own on public.orders for select using (auth.uid() is not null and user_id = auth.uid());
create policy ord_staff_read on public.orders for select using (public.is_staff());
create policy ord_staff_upd on public.orders for update using (public.is_staff()) with check (public.is_staff());
create policy ord_staff_del on public.orders for delete using (public.is_staff());
create index if not exists orders_created_idx on public.orders (created_at desc);
create index if not exists orders_user_idx on public.orders (user_id);

-- 5) Photos et vidéos : stockage public en lecture, envoi réservé à l'équipe.
insert into storage.buckets (id, name, public, file_size_limit)
values ('media', 'media', true, 52428800)
on conflict (id) do update set public = true;
drop policy if exists media_read on storage.objects;
drop policy if exists media_ins on storage.objects;
drop policy if exists media_upd on storage.objects;
drop policy if exists media_del on storage.objects;
create policy media_read on storage.objects for select using (bucket_id = 'media');
create policy media_ins on storage.objects for insert with check (bucket_id = 'media' and public.is_staff());
create policy media_upd on storage.objects for update using (bucket_id = 'media' and public.is_staff());
create policy media_del on storage.objects for delete using (bucket_id = 'media' and public.is_staff());

-- 6) Catalogue de départ (seulement si la boutique est vide).
insert into public.shop (id, data, rev)
values (1, $seed${"settings": {"shopName": "Grace Shop", "slogan": "Portez la grâce.", "city": "Lomé", "whatsapp": "91563836", "tmoney": "91563836", "flooz": "", "paygate": "", "delivery": 1000, "heroText": "L'élégance africaine, livrée à votre porte. Robes en wax, boubous, bijoux et accessoires choisis avec soin.", "flashTitle": "Vente flash de la rentrée", "flashEnd": "2026-10-12T23:59", "codes": [{"code": "GRACE10", "pct": 10}], "freeFrom": 30000}, "categories": ["Femme", "Homme", "Enfant", "Wax & Pagne", "Bijoux", "Accessoires"], "posts": [], "rev": 0, "jewelSubs": ["Bracelets", "Chaînes & colliers", "Bagues", "Boucles d'oreilles", "Montres"], "products": [{"id": "g01", "name": "Robe portefeuille Akosua en wax", "price": 18500, "cat": "Femme", "sizes": ["S", "M", "L", "XL", "XXL"], "colors": ["Indigo", "Safran"], "desc": "Robe portefeuille mi-longue en wax 100 % coton, ceinture à nouer, manches ballon. Se porte au bureau comme en cérémonie.", "stock": 8, "isNew": true, "shape": "dress", "added": 33, "pal": ["#2E2470", "#E7A220", "#F2D9A6"], "oldPrice": 23000}, {"id": "g02", "name": "Robe sirène Afi soirée", "price": 32000, "cat": "Femme", "sizes": ["S", "M", "L", "XL"], "colors": ["Bordeaux", "Noir"], "desc": "Coupe sirène près du corps, tissu satiné stretch, fente arrière. Pour les mariages et les soirées.", "stock": 4, "isNew": true, "shape": "dress", "added": 32, "pal": ["#6E1E3A", "#D9B26F", "#F7E4B8"]}, {"id": "g03", "name": "Ensemble crop top et jupe Yawa", "price": 22000, "cat": "Femme", "sizes": ["S", "M", "L", "XL"], "colors": ["Vert", "Orange"], "desc": "Ensemble deux pièces en pagne : crop top à bretelles et jupe crayon taille haute.", "stock": 6, "isNew": true, "shape": "skirt", "added": 31, "pal": ["#1F5E46", "#E08A3C", "#F2D9A6"]}, {"id": "g04", "name": "Kaba moderne Mawuena", "price": 27500, "cat": "Femme", "sizes": ["S", "M", "L", "XL", "XXL"], "colors": ["Violet", "Doré"], "desc": "Kaba revisité en bazin brodé, coupe ample et élégante, finitions dorées à l'encolure.", "stock": 5, "isNew": false, "shape": "robe", "added": 15, "pal": ["#5B2A88", "#D9B26F", "#F2D9A6"]}, {"id": "g05", "name": "Jupe plissée midi Esi", "price": 11000, "cat": "Femme", "sizes": ["S", "M", "L", "XL"], "colors": ["Bordeaux", "Noir"], "desc": "Jupe plissée fluide, taille haute élastiquée, longueur mi-mollet.", "stock": 9, "isNew": false, "shape": "skirt", "added": 14, "pal": ["#6E1E3A", "#3A0F1E", "#D9B26F"], "oldPrice": 14000}, {"id": "g06", "name": "Blouse en soie Dzifa", "price": 13500, "cat": "Femme", "sizes": ["S", "M", "L", "XL"], "colors": ["Rose", "Blanc"], "desc": "Blouse légère col lavallière, manches longues resserrées aux poignets.", "stock": 7, "isNew": false, "shape": "shirt", "added": 14, "pal": ["#E58FA8", "#F3EEE6", "#D9B26F"]}, {"id": "g07", "name": "Combinaison pantalon Akpene", "price": 19500, "cat": "Femme", "sizes": ["S", "M", "L", "XL"], "colors": ["Noir", "Beige"], "desc": "Combinaison fluide à jambes larges, décolleté croisé, ceinture assortie.", "stock": 5, "isNew": true, "shape": "pants", "added": 27, "pal": ["#0E0E10", "#D9B26F", "#3A3040"]}, {"id": "g08", "name": "T-shirt oversize Grace", "price": 6500, "cat": "Femme", "sizes": ["S", "M", "L", "XL", "XXL"], "colors": ["Blanc", "Noir", "Safran"], "desc": "T-shirt coupe oversize en coton épais, broderie Grace sur la poitrine.", "stock": 20, "isNew": false, "shape": "tshirt", "added": 13, "pal": ["#D9B26F", "#5B2A4A", "#F7E4B8"]}, {"id": "g09", "name": "Boubou brodé trois pièces Kodjo", "price": 35000, "cat": "Homme", "sizes": ["M", "L", "XL", "XXL"], "colors": ["Blanc", "Bleu nuit"], "desc": "Grand boubou en bazin riche avec pantalon et tunique assortis, broderie main au col.", "stock": 4, "isNew": true, "shape": "robe", "added": 25, "pal": ["#EDE6D8", "#B8935A", "#F7E4B8"]}, {"id": "g10", "name": "Chemise wax manches courtes Edem", "price": 12000, "cat": "Homme", "sizes": ["S", "M", "L", "XL", "XXL"], "colors": ["Bleu", "Safran"], "desc": "Chemise en wax, col classique, coupe ajustée. Idéale pour le vendredi au bureau.", "stock": 12, "isNew": false, "shape": "shirt", "added": 12, "pal": ["#2C4FA8", "#E7A220", "#F3EEE6"], "oldPrice": 15000}, {"id": "g11", "name": "Ensemble lin Komlan", "price": 24000, "cat": "Homme", "sizes": ["M", "L", "XL", "XXL"], "colors": ["Sable", "Olive"], "desc": "Chemise col Mao et pantalon en lin respirant, parfait pour la chaleur.", "stock": 6, "isNew": true, "shape": "shirt", "added": 23, "pal": ["#C9B48A", "#6B7046", "#EDE6D8"]}, {"id": "g12", "name": "Pantalon chino ajusté", "price": 14000, "cat": "Homme", "sizes": ["30", "32", "34", "36", "38"], "colors": ["Beige", "Noir"], "desc": "Chino en coton stretch, coupe slim, ourlet à revers.", "stock": 10, "isNew": false, "shape": "pants", "added": 11, "pal": ["#C9B48A", "#8A8A93", "#EDE6D8"]}, {"id": "g13", "name": "Jean coupe droite brut", "price": 15000, "cat": "Homme", "sizes": ["30", "32", "34", "36"], "colors": ["Brut"], "desc": "Denim épais, coupe droite classique, cinq poches.", "stock": 0, "isNew": false, "shape": "pants", "added": 10, "pal": ["#2C3550", "#1A2034", "#8FA0C8"]}, {"id": "g14", "name": "Polo piqué premium", "price": 9000, "cat": "Homme", "sizes": ["S", "M", "L", "XL", "XXL"], "colors": ["Noir", "Blanc", "Bleu nuit"], "desc": "Polo en coton piqué, col côtelé, petit logo doré brodé.", "stock": 15, "isNew": false, "shape": "tshirt", "added": 10, "pal": ["#0E0E10", "#D9B26F", "#3A3040"]}, {"id": "g15", "name": "Ensemble pagne garçon Elom", "price": 9500, "cat": "Enfant", "sizes": ["2 ans", "4 ans", "6 ans", "8 ans"], "colors": ["Vert", "Orange"], "desc": "Chemise et short assortis en pagne, taille élastique pour plus de confort.", "stock": 8, "isNew": true, "shape": "tshirt", "added": 19, "pal": ["#1F5E46", "#E08A3C", "#F2D9A6"]}, {"id": "g16", "name": "Robe de fête fillette Sena", "price": 12500, "cat": "Enfant", "sizes": ["2 ans", "4 ans", "6 ans", "8 ans"], "colors": ["Rose", "Doré"], "desc": "Robe à jupon en tulle et haut en wax, nœud dans le dos. Pour les fêtes et baptêmes.", "stock": 6, "isNew": true, "shape": "dress", "added": 18, "pal": ["#E58FA8", "#D9B26F", "#F7E4B8"]}, {"id": "g17", "name": "T-shirt enfant imprimé", "price": 4000, "cat": "Enfant", "sizes": ["2 ans", "4 ans", "6 ans", "8 ans"], "colors": ["Jaune", "Bleu"], "desc": "T-shirt en coton doux, imprimé motif wax.", "stock": 18, "isNew": false, "shape": "tshirt", "added": 8, "pal": ["#F2C230", "#2C4FA8", "#F7E4B8"], "oldPrice": 5000}, {"id": "g18", "name": "Pagne wax hollandais 6 yards", "price": 16000, "cat": "Wax & Pagne", "sizes": ["Unique"], "colors": ["Indigo", "Rouge", "Vert"], "desc": "Pièce de 6 yards en wax hollandais, couleurs vives qui tiennent au lavage. À confectionner selon vos envies.", "stock": 15, "isNew": false, "shape": "fabric", "added": 8, "pal": ["#2E2470", "#B3261E", "#F2C230"]}, {"id": "g19", "name": "Pagne wax 3 yards motif œil", "price": 8500, "cat": "Wax & Pagne", "sizes": ["Unique"], "colors": ["Safran", "Bleu"], "desc": "Demi-pièce de 3 yards, idéale pour une jupe, une chemise ou un ensemble enfant.", "stock": 20, "isNew": true, "shape": "fabric", "added": 15, "pal": ["#E7A220", "#2C4FA8", "#F7E4B8"]}, {"id": "g20", "name": "Kenté tissé main", "price": 45000, "cat": "Wax & Pagne", "sizes": ["Unique"], "colors": ["Doré", "Vert"], "desc": "Kenté traditionnel tissé main, bandes assemblées. Pour les grandes cérémonies.", "stock": 3, "isNew": true, "shape": "fabric", "added": 14, "pal": ["#1F5E46", "#D9B26F", "#B3261E"]}, {"id": "g21", "name": "Chaîne maille cubaine", "price": 14000, "cat": "Bijoux", "sizes": ["45 cm", "50 cm", "60 cm"], "colors": ["Doré", "Argenté"], "desc": "Maille cubaine épaisse en acier plaqué or, fermoir sécurisé. Ne noircit pas.", "stock": 7, "isNew": true, "shape": "chain", "added": 13, "sub": "Chaînes & colliers", "material": "Acier plaqué or"}, {"id": "g22", "name": "Collier prénom personnalisé", "price": 12000, "cat": "Bijoux", "sizes": ["45 cm", "50 cm"], "colors": ["Doré", "Argenté"], "desc": "Votre prénom en lettres attachées. Indiquez le prénom souhaité dans le message WhatsApp.", "stock": 10, "isNew": true, "shape": "chain", "added": 12, "sub": "Chaînes & colliers", "material": "Acier inoxydable"}, {"id": "g23", "name": "Bague solitaire Grâce", "price": 9000, "cat": "Bijoux", "sizes": ["50", "52", "54", "56", "58"], "colors": ["Argenté", "Doré"], "desc": "Solitaire serti d'un zircon taille brillant, anneau fin.", "stock": 5, "isNew": true, "shape": "ring", "added": 11, "sub": "Bagues", "material": "Argent 925"}, {"id": "g24", "name": "Bague jonc martelé", "price": 6500, "cat": "Bijoux", "sizes": ["52", "54", "56", "58", "60"], "colors": ["Doré"], "desc": "Anneau large à finition martelée, se porte seul ou en accumulation.", "stock": 8, "isNew": false, "shape": "ring", "added": 5, "sub": "Bagues", "material": "Laiton doré"}, {"id": "g25", "name": "Bracelet jonc torsadé", "price": 7500, "cat": "Bijoux", "sizes": ["Unique"], "colors": ["Doré"], "desc": "Jonc ouvert ajustable, finition torsadée brillante.", "stock": 9, "isNew": false, "shape": "bracelet", "added": 4, "oldPrice": 9500, "sub": "Bracelets", "material": "Laiton doré"}, {"id": "g26", "name": "Bracelet perles de verre Krobo", "price": 5000, "cat": "Bijoux", "sizes": ["Unique"], "colors": ["Doré", "Vert"], "desc": "Perles de verre recyclé façonnées à la main, fermeture élastique.", "stock": 14, "isNew": false, "shape": "bracelet", "added": 4, "sub": "Bracelets", "material": "Perles"}, {"id": "g27", "name": "Créoles perles d'eau douce", "price": 6500, "cat": "Bijoux", "sizes": ["Unique"], "colors": ["Doré"], "desc": "Créoles légères ornées de perles naturelles.", "stock": 6, "isNew": false, "shape": "earrings", "added": 3, "sub": "Boucles d'oreilles", "material": "Plaqué or"}, {"id": "g28", "name": "Boucles pendantes Afrique", "price": 8000, "cat": "Bijoux", "sizes": ["Unique"], "colors": ["Doré"], "desc": "Pendentifs en forme de carte d'Afrique, légers et brillants.", "stock": 7, "isNew": true, "shape": "earrings", "added": 6, "sub": "Boucles d'oreilles", "material": "Acier plaqué or"}, {"id": "g29", "name": "Montre cadran champagne", "price": 22000, "cat": "Bijoux", "sizes": ["Unique"], "colors": ["Doré", "Argenté"], "desc": "Bracelet maille milanaise, mouvement quartz, étanche aux éclaboussures.", "stock": 3, "isNew": false, "shape": "watch", "added": 2, "sub": "Montres", "material": "Acier inoxydable"}, {"id": "g30", "name": "Montre homme chrono", "price": 28000, "cat": "Bijoux", "sizes": ["Unique"], "colors": ["Argenté", "Noir"], "desc": "Chronographe, cadran noir et lunette graduée, bracelet acier.", "stock": 3, "isNew": true, "shape": "watch", "added": 4, "sub": "Montres", "material": "Acier inoxydable"}, {"id": "g31", "name": "Sac cabas en pagne", "price": 7500, "cat": "Accessoires", "sizes": ["Unique"], "colors": ["Rouge", "Doré"], "desc": "Grand cabas doublé, anses en simili cuir, poche intérieure zippée.", "stock": 4, "isNew": false, "shape": "bag", "added": 1, "pal": ["#8E2436", "#D9B26F", "#2E2470"]}, {"id": "g32", "name": "Pochette de soirée dorée", "price": 10000, "cat": "Accessoires", "sizes": ["Unique"], "colors": ["Doré", "Noir"], "desc": "Pochette rigide à chaînette amovible, pour vos soirées et cérémonies.", "stock": 5, "isNew": true, "shape": "bag", "added": 2, "pal": ["#D9B26F", "#0E0E10", "#F7E4B8"]}, {"id": "g33", "name": "Foulard gélé à nouer", "price": 5500, "cat": "Accessoires", "sizes": ["Unique"], "colors": ["Violet", "Doré"], "desc": "Gélé en tissu rigide brillant, se noue facilement pour un port élégant.", "stock": 12, "isNew": false, "shape": "skirt", "added": 0, "pal": ["#5B2A88", "#D9B26F", "#F2D9A6"], "oldPrice": 7000}]}$seed$::jsonb, 1)
on conflict (id) do nothing;

-- 7) Propriétaire : remplacez l'adresse ci-dessous si besoin.
insert into public.staff (email) values ('__OWNER_EMAIL__') on conflict do nothing;
