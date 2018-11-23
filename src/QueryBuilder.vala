//	This file is part of FeedReader.
//
//	FeedReader is free software: you can redistribute it and/or modify
//	it under the terms of the GNU General Public License as published by
//	the Free Software Foundation, either version 3 of the License, or
//	(at your option) any later version.
//
//	FeedReader is distributed in the hope that it will be useful,
//	but WITHOUT ANY WARRANTY; without even the implied warranty of
//	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//	GNU General Public License for more details.
//
//	You should have received a copy of the GNU General Public License
//	along with FeedReader.  If not, see <http://www.gnu.org/licenses/>.

public enum FeedReader.QueryType {
	INSERT,
	INSERT_OR_IGNORE,
	INSERT_OR_REPLACE,
	UPDATE,
	SELECT,
	DELETE
}

public class FeedReader.QueryBuilder : GLib.Object {
	private QueryType m_type;
	private string m_table;
	private Gee.List<string> m_fields;
	private Gee.List<string> m_values;
	private Gee.List<string> m_conditions;
	private string? m_orderByColumn = null;
	private bool m_orderDescending = false;
	private uint? m_limit = null;
	private uint? m_offset = null;

	public QueryBuilder(QueryType type, string table)
	{
		m_fields = new Gee.ArrayList<string>();
		m_values = new Gee.ArrayList<string>();
		m_conditions = new Gee.ArrayList<string>();
		m_type = type;
		m_table = table;
	}

	public bool insertValuePair(string field, string value)
	{
		switch(m_type)
		{
			case QueryType.INSERT:
			case QueryType.INSERT_OR_IGNORE:
			case QueryType.INSERT_OR_REPLACE:
				m_fields.add(field);
				m_values.add(value);
				return true;
		}
		Logger.error("insertValuePair");
		return false;
	}

	public bool selectField(string field)
	{
		if(m_type == QueryType.SELECT)
		{
			m_fields.add(field);
			return true;
		}
		Logger.error("selectField");
		return false;
	}

	public bool updateValuePair(string field, string value, bool isString = false)
	{
		if(m_type == QueryType.UPDATE)
		{
			m_fields.add(field);

			string quoted_value = isString ? SQLite.quote_string(value) : value;
			m_values.add(quoted_value);
			return true;
		}
		Logger.error("updateValuePair");

		return false;
	}

	public bool addEqualsCondition(string field, string value, bool positive = true, bool isString = false)
	{
		if(m_type == QueryType.UPDATE
		|| m_type == QueryType.SELECT
		|| m_type == QueryType.DELETE)
		{
			string condition = "%s = %s";

			string quoted_value = isString ? SQLite.quote_string(value) : value;

			if(!positive)
				condition = "NOT " + condition;

			m_conditions.add(condition.printf(field, quoted_value));
			return true;
		}
		Logger.error("addEqualsConditionString");
		return false;
	}

	public bool addCustomCondition(string condition)
	{
		if(m_type == QueryType.UPDATE
		|| m_type == QueryType.SELECT
		|| m_type == QueryType.DELETE)
		{
			m_conditions.add(condition);
			return true;
		}
		Logger.error("addCustomCondition");
		return false;
	}

	public bool addRangeConditionString(string field, Gee.List<string> values, bool instr = false)
	{
		if(!instr)
		{
			if(m_type == QueryType.UPDATE
			|| m_type == QueryType.SELECT
			|| m_type == QueryType.DELETE)
			{
				if (values.size == 0)
				{
					m_conditions.add("1 <> 1");
				}
				else {
					var compound_values = new GLib.StringBuilder();
					foreach(string value in values)
					{
						compound_values.append(SQLite.quote_string(value));
						compound_values.append(", ");
					}
					compound_values.erase(compound_values.len - 2);
					m_conditions.add("%s IN (%s)".printf(field, compound_values.str));
				}
				return true;
			}
		}
		else
		{
			if(m_type == QueryType.UPDATE
			|| m_type == QueryType.SELECT
			|| m_type == QueryType.DELETE)
			{
				foreach(string value in values)
				{
					this.addCustomCondition("instr(field, %s) > 0".printf(SQLite.quote_string(value)));
				}
			}
			return true;
		}

		Logger.error("addRangeConditionString");
		return false;
	}

	public bool addRangeConditionInt(string field, Gee.List<int> values)
	{
		if(m_type == QueryType.UPDATE
		|| m_type == QueryType.SELECT
		|| m_type == QueryType.DELETE)
		{
			if (values.size == 0)
			{
				m_conditions.add("1 <> 1");
			}
			else {
				var compound_values = new GLib.StringBuilder();
				foreach(int value in values)
				{
					compound_values.append(value.to_string());
					compound_values.append(", ");
				}
				compound_values.erase(compound_values.len - 2);
				m_conditions.add("%s IN (%s)".printf(field, compound_values.str));
			}
			return true;
		}
		Logger.error("addRangeConditionInt");
		return false;
	}

	public void orderBy(string field, bool desc)
	requires (m_type == QueryType.SELECT)
	{
		m_orderByColumn = field;
		m_orderDescending = desc;
	}

	public void limit(uint limit)
	requires (m_type == QueryType.SELECT)
	{
		m_limit = limit;
	}

	public void offset(uint offset)
	requires (m_type == QueryType.SELECT)
	{
		m_offset = offset;
	}

	public string to_string()
	{
		var query = new GLib.StringBuilder();
		switch(m_type)
		{
			case QueryType.INSERT:
			case QueryType.INSERT_OR_IGNORE:
			case QueryType.INSERT_OR_REPLACE:
				query.append("INSERT ");

				if(m_type == QueryType.INSERT_OR_IGNORE)
					query.append("OR IGNORE ");
				else if(m_type == QueryType.INSERT_OR_REPLACE)
					query.append("OR REPLACE ");

				query.append_printf("INTO %s (", m_table);
				StringUtils.stringbuilder_append_join(query, m_fields, ", ");
				query.append(") VALUES (");
				StringUtils.stringbuilder_append_join(query, m_values, ", ");
				query.append_c(')');
				break;

			case QueryType.UPDATE:
				query.append_printf("UPDATE %s SET ", m_table);

				assert(m_fields.size > 0);
				for(int i = 0; i < m_fields.size; i++)
				{
					if (i > 0)
						query.append(", ");

					query.append(m_fields.get(i));
					query.append(" = ");
					query.append(m_values.get(i));
				}

				append_conditions(query);
				break;


			case QueryType.DELETE:
				query.append("DELETE FROM ");
				query.append(m_table);
				append_conditions(query);
				break;


			case QueryType.SELECT:
				query.append("SELECT ");
				StringUtils.stringbuilder_append_join(query, m_fields, ", ");
				query.append_printf(" FROM %s", m_table);

				append_conditions(query);

				if (m_orderByColumn != null) {
					query.append_printf(
						" ORDER BY %s COLLATE NOCASE %s",
						m_orderByColumn,
						m_orderDescending ? "DESC" : "ASC");
				}

				if (m_limit != null)
					query.append_printf(" LIMIT %u", m_limit);

				if (m_offset != null)
					query.append_printf(" OFFSET %u", m_offset);
				break;
		}

		return query.str;
	}

	private void append_conditions(StringBuilder query)
	{
		if(m_conditions.size == 0)
			return;

		query.append(" WHERE ");
		StringUtils.stringbuilder_append_join(query, m_conditions, " AND ");
	}

	public void print()
	{
		Logger.debug(to_string());
	}
}
