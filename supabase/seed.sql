-- Development seed: categories and a small starter catalogue of GENERIC medicines.
-- No users, pharmacies, stock or prices are seeded — real data comes from the app.
-- The production catalogue is curated by admins (proposals from pharmacists, reviewed in the admin panel).
-- Safe to run more than once (conflicts are skipped).

insert into public.medicine_categories (name_ar, name_en, sort_order) values
  ('مسكنات وخافضات حرارة', 'Pain and fever', 10),
  ('مضادات حيوية', 'Antibiotics', 20),
  ('الجهاز الهضمي', 'Digestive system', 30),
  ('الجهاز التنفسي والسعال', 'Respiratory and cough', 40),
  ('الحساسية', 'Allergy', 50),
  ('السكري', 'Diabetes', 60),
  ('الضغط والقلب', 'Blood pressure and heart', 70),
  ('فيتامينات ومكملات', 'Vitamins and supplements', 80),
  ('الأطفال', 'Children', 90),
  ('العناية بالبشرة', 'Skin care', 100),
  ('مستلزمات طبية', 'Medical supplies', 110)
on conflict do nothing;

insert into public.medicines (category_id, name_ar, name_en, active_ingredient, strength, dosage_form, package_description, catalog_status)
select c.id, v.name_ar, v.name_en, v.ingredient, v.strength, v.form, v.pack, 'approved'
from (values
  ('مسكنات وخافضات حرارة', 'باراسيتامول', 'Paracetamol', 'paracetamol', '500mg', 'أقراص', 'علبة 20 قرص'),
  ('مسكنات وخافضات حرارة', 'باراسيتامول شراب', 'Paracetamol syrup', 'paracetamol', '120mg/5ml', 'شراب', 'زجاجة 100 مل'),
  ('مسكنات وخافضات حرارة', 'إيبوبروفين', 'Ibuprofen', 'ibuprofen', '400mg', 'أقراص', 'علبة 20 قرص'),
  ('مسكنات وخافضات حرارة', 'ديكلوفيناك', 'Diclofenac', 'diclofenac sodium', '50mg', 'أقراص', 'علبة 20 قرص'),
  ('مسكنات وخافضات حرارة', 'أسبرين', 'Aspirin', 'acetylsalicylic acid', '100mg', 'أقراص', 'علبة 30 قرص'),
  ('مضادات حيوية', 'أموكسيسيلين', 'Amoxicillin', 'amoxicillin', '500mg', 'كبسولة', 'علبة 16 كبسولة'),
  ('مضادات حيوية', 'أموكسيسيلين وحمض الكلافولانيك', 'Amoxicillin/Clavulanate', 'amoxicillin + clavulanic acid', '1g', 'أقراص', 'علبة 14 قرص'),
  ('مضادات حيوية', 'أزيثرومايسين', 'Azithromycin', 'azithromycin', '500mg', 'أقراص', 'علبة 3 أقراص'),
  ('الجهاز الهضمي', 'أوميبرازول', 'Omeprazole', 'omeprazole', '20mg', 'كبسولة', 'علبة 14 كبسولة'),
  ('الجهاز الهضمي', 'دومبيريدون', 'Domperidone', 'domperidone', '10mg', 'أقراص', 'علبة 30 قرص'),
  ('الجهاز الهضمي', 'محلول معالجة الجفاف', 'Oral rehydration salts', 'oral rehydration salts', null, 'أكياس', 'علبة 10 أكياس'),
  ('الجهاز التنفسي والسعال', 'شراب سعال', 'Cough syrup', 'dextromethorphan', '15mg/5ml', 'شراب', 'زجاجة 120 مل'),
  ('الجهاز التنفسي والسعال', 'سالبوتامول بخاخ', 'Salbutamol inhaler', 'salbutamol', '100mcg', 'بخاخ', 'علبة 200 جرعة'),
  ('الحساسية', 'لوراتادين', 'Loratadine', 'loratadine', '10mg', 'أقراص', 'علبة 10 أقراص'),
  ('الحساسية', 'سيتيريزين', 'Cetirizine', 'cetirizine', '10mg', 'أقراص', 'علبة 20 قرص'),
  ('السكري', 'ميتفورمين', 'Metformin', 'metformin', '500mg', 'أقراص', 'علبة 60 قرص'),
  ('الضغط والقلب', 'أملوديبين', 'Amlodipine', 'amlodipine', '5mg', 'أقراص', 'علبة 30 قرص'),
  ('الضغط والقلب', 'أتينولول', 'Atenolol', 'atenolol', '50mg', 'أقراص', 'علبة 28 قرص'),
  ('فيتامينات ومكملات', 'فيتامين ج', 'Vitamin C', 'ascorbic acid', '1000mg', 'أقراص فوارة', 'أنبوب 20 قرص'),
  ('فيتامينات ومكملات', 'فيتامين د3', 'Vitamin D3', 'cholecalciferol', '1000IU', 'كبسولة', 'علبة 30 كبسولة'),
  ('فيتامينات ومكملات', 'حديد وحمض الفوليك', 'Iron and folic acid', 'ferrous fumarate + folic acid', null, 'كبسولة', 'علبة 30 كبسولة'),
  ('الأطفال', 'قطرات فيتامين د للأطفال', 'Vitamin D drops for children', 'cholecalciferol', '400IU/drop', 'قطرة', 'زجاجة 20 مل'),
  ('العناية بالبشرة', 'كريم مرطب', 'Moisturising cream', 'glycerin', null, 'كريم', 'أنبوب 100 غ'),
  ('مستلزمات طبية', 'ميزان حرارة رقمي', 'Digital thermometer', null, null, 'جهاز', 'قطعة واحدة'),
  ('مستلزمات طبية', 'ضمادات لاصقة', 'Adhesive bandages', null, null, 'ضمادات', 'علبة 20 قطعة')
) as v(category, name_ar, name_en, ingredient, strength, form, pack)
join public.medicine_categories c on c.name_ar = v.category
on conflict do nothing;
