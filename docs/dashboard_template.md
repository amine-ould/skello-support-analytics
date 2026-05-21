# Template du dashboard hebdomadaire Support
 
> **Cible** : Lorette, Lead Support
> **Rituel** : lundi matin, ~30 min
> **Période par défaut** : semaine S-1 (lundi → dimanche), comparée à S-2
> **Outil cible** : Metabase / Tableau / Looker (ou notebook dans un premier temps)

---

## Principes de conception

1. **Lecture en moins de 2 minutes.** Les KPI clés en haut, le détail en bas.
2. **Toujours une comparaison.** Un chiffre absolu ne raconte pas d'histoire ; un delta vs S-1 ou vs cible, oui.
3. **Granularité progressive** : équipe → individu → conversation unitaire.
4. **Filtres globaux unifiés** en haut : période, agent, tag, priorité.
5. **Pas de viz décorative** : chaque graphique répond à une question business explicite.

---

## Filtres globaux

| Filtre | Valeur par défaut |
|---|---|
| Période | Semaine S-1 |
| Agent | Tous |
| Tag | Tous |
| Scope | Conv. passées par Support |

---

## Section 1 — Bandeau KPI (4 cartes)

> **Question** : Comment va le support cette semaine vs la précédente ?

| KPI | Comparaison | Cible suggérée |
|---|---|---|
| 📥 **Volume de conversations** | Δ% vs S-2 | — |
| ✅ **% FRT < 5 min** | Δpp vs S-2 | **>70 %** (à valider) |
| ⭐ **CSAT positive** (note ≥ 4) | Δpp vs S-2 | **>90 %** |
| ⏱ **Résolution médiane** | Δ% vs S-2 | — |

**Choix de design** :
- Cartes "KPI + delta + flèche" : pattern standard, immédiatement lisible.
- Médiane (pas moyenne) pour la résolution : robuste aux conv exceptionnellement longues.
- Comparaison à S-2 (pas au mois) car le pattern hebdo varie davantage.

---

## Section 2 — Performance individuelle (tableau)

> **Question** : Y a-t-il des écarts de performance ou de charge entre agents ?

| Colonne | Définition |
|---|---|
| Agent | Prénom (via `dim_support_agents`) |
| Conv. répondues (1ᵉʳ) | `first_responder_admin_id = agent` |
| FRT médian | sur les conv 1ʳᵉ-replied |
| **% FRT <5min** | idem |
| Conv. one-touch (%) | proxy d'efficacité |
| CSAT moyenne reçue | sur `csat_rated_teammate_id` |
| **% CSAT positive** | idem |

**Choix** :
- Couleur sur `% FRT <5min` et `% CSAT positive` : vert ≥ cible, orange entre seuil et cible, rouge en dessous.
- Tri par `% CSAT positive` décroissant.
- **Pas de classement (1ᵉʳ, 2ᵉ...)** : on évite la mise en compétition ; le management voit les écarts.

---

## Section 3 — Heatmap d'activité (jour × heure)

> **Question** : Quand l'équipe est-elle le plus sollicitée ? Le staffing est-il aligné avec les pics ?

Heatmap **7 lignes (lundi → dimanche) × 24 colonnes (heures)**, valeur = nombre de conversations ouvertes.

**Choix** :
- Échelle **séquentielle** (du clair au foncé) — on regarde un volume, pas un écart.
- Période **dernier mois** (pas une semaine) pour avoir un pattern stable.
- Pourquoi cette viz : un line chart de 7 courbes serait illisible, un bar chart agrégé écraserait l'info (pic mardi 10h vs jeudi 15h).

**Action attendue** : si pic systématique mardi 14h-16h sans staffing → ajuster planning Skello.

---

## Section 4 — Évolution temporelle (line chart double-axe)

> **Question** : La qualité tient-elle dans le temps ?

Sur les **12 dernières semaines** :
- Y gauche : **% FRT <5min** (ligne bleue)
- Y droit : **% CSAT positive** (ligne verte)
- Ligne horizontale pointillée = cible

**Choix** : 2 KPIs sur le même graph → valider visuellement les corrélations (un drop FRT entraîne-t-il une dégradation CSAT 1-2 semaines après ?).

---

## Section 5 — Distribution du FRT (histogramme)

> **Question** : Bimodal (=astreinte cassée) ou concentré (=cible : pousser vers <5min) ?

Buckets : `<1min` / `1-5min` / `5-30min` / `30min-2h` / `2-24h` / `>24h`
Code couleur progressif (vert → rouge), aligné avec les seuils SLA.

---

## Section 6 — Top tags (bar chart horizontal + Δ vs S-1)

> **Question** : Quels sujets dominent ? Y a-t-il une explosion (= incident produit à remonter) ?

Top 10 tags semaine, avec variation vs S-1 (pastille colorée).

**Action attendue** : si tag `Bug-pointeuse` passe de 12 à 45 conv en une semaine → ticket Slack #produit immédiat depuis le meeting.

---

## Section 7 — Conversations CSAT 1-2 (tableau drill-down)

> **Question** : Quelles conversations ont mal tourné, pour debrief en équipe ?

| Lien Intercom | Agent | Note | Extrait remark | FRT | Tags |
|---|---|---|---|---|---|

**Choix** : ramener du **qualitatif** dans une réunion data-heavy. 3-5 cas par semaine pour un debrief constructif.

---

## Annexe — Indicateur "santé du dashboard"

Footer discret :
- 📊 Dernière mise à jour : `MAX(_sdc_extracted_at)`
- ⚠️ % de conv sans CSAT cette semaine (= taux de réponse au sondage)
- ⚠️ % de conv sans assignation (anomalie potentielle)

Pour que Lorette **fasse confiance** au dashboard.
