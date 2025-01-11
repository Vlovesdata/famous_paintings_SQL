SELECT * FROM artist;
SELECT * FROM canvas_size;
SELECT * FROM image_link;
SELECT * FROM museum;
SELECT * FROM museum_hurs;
SELECT * FROM product_size;
SELECT * FROM subject;
SELECT * FROM work;

#----------------------- FIRST, CLEANING ---------------
# putting state names to null or digit city names
SELECT *
FROM museum
WHERE city REGEXP '^[0-9]+$' OR city IS NULL;
UPDATE museum
SET city = state
WHERE city REGEXP '^[0-9]+$' OR city IS NULL;
# fixing postal codes
SELECT *
FROM museum
WHERE postal LIKE '% %';
UPDATE museum
SET postal = REPLACE(postal, ' ', '')
WHERE postal LIKE '% %';
# fixing phone table
SELECT *
FROM museum
WHERE phone REGEXP '[^0-9+ ]' OR phone LIKE '% %' OR phone LIKE '%-%' OR phone LIKE '%(%';
UPDATE museum
SET phone = REPLACE(phone, '-', '');
UPDATE museum
SET phone = REPLACE(phone, '(', '');
UPDATE museum
SET phone = REPLACE(phone, ')', '');
UPDATE museum
SET phone = REPLACE(phone, ' ', '');
SELECT *
FROM museum
WHERE phone NOT LIKE '+%';
UPDATE museum
SET phone = CONCAT('+', phone)
WHERE phone NOT LIKE '+%';


#1)--------------- Fetch all the paintings which are not displayed on any museums ----------

SELECT *
FROM work
WHERE museum_id IS NULL;

#2) ----------------- Are there museuems without any paintings -----------------

SELECT * 
FROM museum m
	WHERE NOT EXISTS (SELECT 1 FROM work w
					 WHERE w.museum_id=m.museum_id);

#3) --------------------- How many paintings have an asking price of more than their regular price? -------------------------------

SELECT COUNT(*)
FROM product_size
WHERE sale_price > regular_price;

#4) -----------------------  Identify the paintings whose asking price is less than 50% of its regular price ---------------------------
SELECT w.name AS work_name,
m.name AS museum_name
FROM product_size p
JOIN work w
ON p.work_id = w.work_id
JOIN museum m
ON w.museum_id = m.museum_id
WHERE p.sale_price < (p.regular_price * 0.5)
GROUP BY work_name, museum_name;

#5) -------------Which canva size costs the most? --------------
WITH ranked_prices AS (
    SELECT 
        c.label,
        p.sale_price,
        RANK() OVER (ORDER BY p.sale_price DESC) AS rnk
    FROM product_size p
    JOIN canvas_size c
    ON p.size_id = c.size_id
)
SELECT label, sale_price
FROM ranked_prices
WHERE rnk = 1;




#6) ---------  Delete duplicate records from work, product_size, subject and image_link tables -------------------
# ---- product size ------
WITH ranked_rows AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (PARTITION BY size_id, sale_price ORDER BY work_id) AS row_num
    FROM product_size
)
DELETE FROM product_size
WHERE work_id IN (
    SELECT work_id
    FROM ranked_rows
    WHERE row_num > 1
);

# ------ work --------
WITH ranked_rows AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (PARTITION BY name, artist_id ORDER BY work_id) AS row_num
    FROM work
)
DELETE FROM work
WHERE work_id IN (
    SELECT work_id
    FROM ranked_rows
    WHERE row_num > 1
);

# ----- subjetc -----

WITH ranked_rows AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (PARTITION BY subject ORDER BY work_id) AS row_num
    FROM subject
)
DELETE FROM subject
WHERE work_id IN (
    SELECT work_id
    FROM ranked_rows
    WHERE row_num > 1
);

# -------- image_link ----------

WITH ranked_rows AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (PARTITION BY url, thumbnail_small_url, thumbnail_large_url ORDER BY work_id) AS row_num
    FROM image_link
)
DELETE FROM image_link
WHERE work_id IN (
    SELECT work_id
    FROM ranked_rows
    WHERE row_num > 1
);

#7) ---------------------  Museum_Hours table has 1 invalid entry. Identify it and remove it. ----------

SELECT *
FROM Museum_Hours
WHERE LOWER(day) NOT IN ('sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday');
UPDATE Museum_Hours
SET day = 'Thursday'
WHERE LOWER(day) = 'thusday';

#8) ------------------Fetch the top 10 most famous painting subject------------

SELECT *
FROM work w
JOIN subject s
ON s.work_id = w.work_id ;

SELECT * 
FROM (
SELECT s.subject,
COUNT(*) AS no_of_paintings,
RANK() OVER(ORDER BY COUNT(*) DESC) AS ranking
FROM work w
JOIN subject s
ON s.work_id = w.work_id  
GROUP BY s.subject) x
WHERE ranking <= 10;

#9) --------------------- identify the musuems which are open on both SUnday and Monday, display the museum name, city ----------------------------

SELECT m.name AS museum_name,
m.city
FROM museum_hours mh1
JOIN museum m
ON m.museum_id = mh1.museum_id
WHERE day = 'Sunday'
AND EXISTS (SELECT 1 
FROM museum_hours mh2
WHERE mh2.day = 'Monday'
AND mh1.museum_id = mh2.museum_id);

#10)----------How many museums are open every single day?---------

SELECT mh.museum_id, 
m.name AS museum_name
FROM museum_hours mh
JOIN museum m
ON m.museum_id = mh.museum_id
GROUP BY mh.museum_id, m.name
HAVING COUNT(DISTINCT mh.day) = 7;


#11) ----------Which are the top 5 most popular museum? (Popularity is defined based on most no of paintings in a museum)------------


SELECT *
FROM (
SELECT m.name AS museum_name, 
COUNT(*) AS no_painting,
RANK() OVER(ORDER BY COUNT(*) DESC) AS ranking
FROM museum m
JOIN work w
ON m.museum_id = w.museum_id 
GROUP BY m.name) x
WHERE x.ranking <= 5
;


#12) -----------------Who are the top 5 most popular artist? (Popularity is defined based on most no of paintings done by an artist)------------
SELECT *
FROM (
SELECT a.full_name AS artist_name,
COUNT(*) AS no_paintings,
RANK() OVER(ORDER BY COUNT(*) DESC) AS rnk
FROM artist a
JOIN work w
ON w.artist_id = a.artist_id
GROUP BY a.full_name) x
WHERE x.rnk <= 5;

#13)-------Which museum has the most no of most popular painting style? ------

WITH popular_style AS (
	SELECT style,
    RANK() OVER(ORDER BY COUNT(*) DESC) AS rnk
    FROM work
    GROUP BY style ),
    
museum_cte AS (
	SELECT m.name AS museum_name,
    ps.style AS style,
    COUNT(*) AS number_paintings,
    RANK() OVER(ORDER BY COUNT(*) DESC) AS rnk
    FROM work w
    JOIN museum m
    ON M.museum_id = w.museum_id
    JOIN popular_style ps
    ON ps.style = w.style
    WHERE ps.rnk = 1
    GROUP BY  m.name, ps.style)
SELECT museum_name, style, number_paintings
FROM museum_cte
WHERE rnk=1;

#14)------------------- Identify the artists whose paintings are displayed in multiple countries--------------------

SELECT a.full_name,
COUNT(DISTINCT m.country) AS no_of_countries
FROM artist a
JOIN work w
ON w.artist_id = a.artist_id
JOIN museum m
ON m.museum_id = w.museum_id
GROUP BY a.full_name
HAVING COUNT(DISTINCT m.country) >1;


#15) --------------------- WHICH MUSEUM IS OPEN FOR THE LONGEST DURING A DAY, DISPLAY MUSEUM NAME, STATE, DURATION AND WHICH DAY ------------------------------------
UPDATE museum_hours
SET open = REPLACE(open, ':AM', ' AM'),
    open = REPLACE(open, ':PM', ' PM'),
    close = REPLACE(close, ':AM', ' AM'),
    close = REPLACE(close, ':PM', ' PM');
 
 
 
 SELECT * 
 FROM (
SELECT
    m.name AS museum_name,
    mh.day,
    m.state,
    TIMEDIFF(
        STR_TO_DATE(CONCAT('2023-01-01 ', close), '%Y-%m-%d %h:%i %p'),
        STR_TO_DATE(CONCAT('2023-01-01 ', open), '%Y-%m-%d %h:%i %p')
    ) AS duration,
    RANK() OVER ( ORDER BY (TIMEDIFF(
        STR_TO_DATE(CONCAT('2023-01-01 ', close), '%Y-%m-%d %h:%i %p'),
        STR_TO_DATE(CONCAT('2023-01-01 ', open), '%Y-%m-%d %h:%i %p')
    ))) AS rnk
FROM museum_hours mh
JOIN museum m
ON m.museum_id = mh.museum_id ) AS x
WHERE x.rnk=1;



#16) --------------------- Display the country and the city with most number of museums. Output 2 seperate columns to mention the city and country. If there are multiple value, seperate them with comma -------------------------------------

WITH cte_country AS (
	SELECT country, count(1),
    RANK () OVER(ORDER BY count(1) DESC ) AS rnk
	FROM museum
	GROUP BY country ),
cte_city AS (
	SELECT city, count(1),
    RANK () OVER(ORDER BY count(1) DESC ) AS rnk
	FROM museum
	GROUP BY city )
    
SELECT country, city
FROM cte_country
CROSS JOIN cte_city
WHERE cte_country.rnk = 1
AND cte_city.rnk = 1;

	
#17) ----------------------Identify the artist and the museum where the most expensive and least expensive painting is placed. Display the artist name, sale_price, painting name, museum name, museum city and canvas label------------

WITH price_cte AS (
	SELECT *,
    RANK() OVER(ORDER BY sale_price DESC) AS rnk_desc,
    RANK() OVER(ORDER BY sale_price ) AS rnk_asc
    FROM product_size ps )

SELECT a.full_name,
price_cte.sale_price,
w.name AS painting_name,
m.name AS museum_name,
m.city,
cs.label
FROM price_cte
JOIN work w
ON price_cte.work_id = w.work_id
JOIN museum m
ON m.museum_id = w.museum_id
JOIN canvas_size cs
ON cs.size_id = price_cte.size_id
JOIN artist a
ON a.artist_id = w.artist_id
WHERE rnk_asc = 1 OR rnk_desc=1;


#18)---------Which country has the 5th highest no of paintings?--------

WITH cte AS (
    SELECT 
        m.country,
        COUNT(*) AS no_of_paintings,
        RANK() OVER (ORDER BY COUNT(*) DESC) AS rnk
    FROM museum m
    JOIN work w
    ON m.museum_id = w.museum_id
    GROUP BY m.country
)
SELECT country
FROM cte
WHERE rnk=5;


#19) -------------Which are the 3 most popular and 3 least popular painting styles?--------

WITH ranking_cte AS (
	SELECT style,
    COUNT(*) AS no_of_paintings,
    RANK() OVER(ORDER BY COUNT(*) DESC) AS rnk_desc,
    RANK() OVER(ORDER BY COUNT(*) ) AS rnk
    FROM work
    GROUP BY style)

SELECT style, no_of_paintings
FROM ranking_cte
WHERE rnk_desc <=3 OR rnk<=3;


#20) -------Which artist has the most no of Portraits paintings outside USA?. Display artist name, no of paintings and the artist nationality -----------





SELECT full_name AS artist_name,
nationality,
no_of_paintings
FROM (
	SELECT a.full_name,
	a.nationality,
	COUNT(*) AS no_of_paintings,
	RANK() OVER(ORDER BY COUNT(*) DESC) AS rnk
	FROM subject s
	JOIN work w
	ON s.work_id = w.work_id
	JOIN artist a
	ON a.artist_id = w.artist_id
	JOIN museum m
	ON m.museum_id = w.museum_id
	WHERE s.subject = 'Portraits' AND m.country != 'USA' 
	GROUP BY a.full_name, a.nationality) x
WHERE rnk=1;



