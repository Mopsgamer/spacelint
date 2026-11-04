const sqlQuery = `
SELECT * FROM users
WHERE name = '// not a real comment'
/* and this is not a block comment either */
`;
