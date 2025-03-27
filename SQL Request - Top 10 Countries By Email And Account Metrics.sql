WITH email_metrics_cte AS (
  -- CTE для обчислення метрик по email (відправлені, відкриті листи, переходи)
  SELECT
    DATE_ADD(session.date, INTERVAL sent.sent_date DAY) AS date,
    session_params.country AS country,
    0 AS sent_interval,
    0 AS is_verified,
    0 AS is_unsubscribed,
    0 AS account_cnt,
    COUNT(DISTINCT sent.id_message) AS email_sent,
    COUNT(DISTINCT open.id_message) AS email_open,
    COUNT(DISTINCT visit.id_message) AS email_visit
  FROM
    `DA.session` AS session
  JOIN
    `DA.session_params` AS session_params
  ON
    session.ga_session_id = session_params.ga_session_id
  JOIN
    `DA.account_session` AS account_session
  ON
    session.ga_session_id = account_session.ga_session_id
  JOIN
    `DA.account` AS account
  ON
    account_session.account_id = account.id
  JOIN
    `DA.email_sent` AS sent
  ON
    account.id = sent.id_account
  LEFT JOIN
    `DA.email_open` AS open
  ON
    sent.id_message = open.id_message
  LEFT JOIN
    `DA.email_visit` AS visit
  ON
    sent.id_message = visit.id_message
  GROUP BY
    date, country, sent_interval, is_verified, is_unsubscribed


UNION ALL
  -- Обчислення метрик по акаунтах
  SELECT
    session.date AS date,
    session_params.country AS country,
    account.send_interval AS sent_interval, -- інтервал
    account.is_verified AS is_verified, -- Підтверджені акаунти
    account.is_unsubscribed AS is_unsubscribed, -- Відписані акаунти
    COUNT(DISTINCT account.id) AS account_cnt, -- Кількість акаунтів
    0 AS email_sent,
    0 AS email_open,
    0 AS email_visit
  FROM
    `DA.account` AS account
  JOIN
    `DA.account_session` AS account_session
  ON
    account.id = account_session.account_id
  JOIN
    `DA.session` AS session
  ON
    account_session.ga_session_id = session.ga_session_id
  JOIN
    `DA.session_params` AS session_params
  ON
    account_session.ga_session_id = session_params.ga_session_id
  GROUP BY
    session.date, country, sent_interval, is_verified, is_unsubscribed
),

aggregated_metrics_cte AS (
  -- CTE для агрегації метрик на рівні дати та країни
  SELECT
    email_metrics_cte.date AS date,
    email_metrics_cte.country AS country,
    ROUND(AVG(email_metrics_cte.sent_interval), 2) AS sent_interval,
    SUM(email_metrics_cte.is_verified) AS is_verified,
    SUM(email_metrics_cte.is_unsubscribed) AS is_unsubscribed,
    SUM(email_metrics_cte.account_cnt) AS account_cnt,
    SUM(email_metrics_cte.email_sent) AS email_sent,
    SUM(email_metrics_cte.email_open) AS email_open,
    SUM(email_metrics_cte.email_visit) AS email_visit
  FROM
    email_metrics_cte
  GROUP BY
    date, country
),

ranked_metrics_cte AS (
  -- CTE для обчислення глобальних метрик і рейтингу країн
  SELECT
    *,
    SUM(aggregated_metrics_cte.account_cnt) OVER(PARTITION BY country) AS total_country_account_cnt, -- Загальна кількість акаунтів по країні
    SUM(aggregated_metrics_cte.email_sent) OVER(PARTITION BY country) AS total_country_sent_cnt -- Загальна кількість відправлених листів по країні
  FROM
    aggregated_metrics_cte
)

-- Фінальний вибір із ранжуванням та фільтрацією
SELECT
  *
FROM(
  -- Підзапит для можливості подальшої фільтрації
  SELECT
    *,
    DENSE_RANK() OVER(ORDER BY total_country_account_cnt DESC) AS rank_total_country_account_cnt, -- Рейтинг країн за кількістю акаунтів
    DENSE_RANK() OVER(ORDER BY total_country_sent_cnt DESC) AS rank_total_country_sent_cnt -- Рейтинг країн за кількістю листів
  FROM
    ranked_metrics_cte)
WHERE
  rank_total_country_account_cnt <= 10
  OR rank_total_country_sent_cnt <= 10