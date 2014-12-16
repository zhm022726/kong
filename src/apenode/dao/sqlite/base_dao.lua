-- Copyright (C) Mashape, Inc.

local BaseDao = {}
BaseDao.__index = BaseDao

setmetatable(BaseDao, {
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    self:_init(...)
    return self
  end
})

function BaseDao:_init(database)
  self._db = database
end

function BaseDao:save(entity)
  self.insert_stmt:bind_names(entity)
  local inserted_id, err = self:exec_insert_stmt(self.insert_stmt)
  if err then
    return nil, err
  end

  -- We need to get the inserted row because SQLite might
  -- change the type of the inserted values
  -- or not have saved some values from the entity
  -- TODO: Actually we should have a model layer/ORM so we don't need to do that
  return self:get_by_id(inserted_id)
end

function BaseDao:update(entity)
  self.update_stmt:bind_names(entity)
  local updated, err = self:exec_stmt(self.update_stmt)
  if err then
    return nil, err
  end

  -- We need to get the inserted row because SQLite might
  -- change the type of the inserted values
  -- or not have saved some values from the entity
  -- TODO: Actually we should have a model layer/ORM so we don't need to do that
  return self:get_by_id(entity.id)
end

function BaseDao:delete(entity)
  self.delete_stmt:bind_values(entity.id)
  return self:exec_stmt(self.delete_stmt)
end

function BaseDao:get_by_id(id)
  self.select_by_id_stmt:bind_values(id)
  return self:exec_select_stmt(self.select_by_id_stmt)
end

function BaseDao:get_all(page, size)
  -- TODO all in one query
  local results, err = self:exec_paginated_stmt(self.select_all_stmt, page, size)
  if err then
    return nil, nil, err
  end

  local count, err = self:exec_stmt(self.select_count_stmt)
  if err then
    return nil, nil, err
  end

  return results, count
end

function BaseDao:get_error(status)
  return {
    status = result,
    message = self._db:errmsg()
  }
end

-- Execute a statement supposed to return a page
-- @param stmt A sqlite3 prepared statement
-- @param page The page to query
-- @param size The size of the page
-- @return A list of tables representing the fetched entities, nil if error
-- @return A sqlite3 status code if error
function BaseDao:exec_paginated_stmt(stmt, page, size)
  if not page then page = 1 end
  if not size then size = 30 end
  size = math.min(size, 100)

  local results = {}
  local start_offset = ((page - 1) * size)

  -- values binding
  stmt:bind_names { page = start_offset, size = size }

  -- Execute query
  local step_result = stmt:step()

  -- Aggregate rows
  while step_result == sqlite3.ROW do
    table.insert(results, stmt:get_named_values())
    step_result = stmt:step()
  end

  -- Reset statement and get status code
  local status = stmt:reset()

  -- Error handling
  if step_result == sqlite3.DONE and status == sqlite3.OK then
    return results
  else
    return nil, self:get_error(status)
  end
end

-- Execute a statement supposed to return one row
-- @param stmt A sqlite3 prepared statement
-- @return A table representing the fetched entity, nil if error
-- @return A sqlite3 status code if error
function BaseDao:exec_select_stmt(stmt)
  -- Execute query
  local results
  local step_result = stmt:step()

  -- Aggregate rows
  if step_result == sqlite3.ROW then
    results = stmt:get_named_values()
    step_result = stmt:step()
  end

  -- Reset statement and get status code
  local status = stmt:reset()

  -- Error handling
  if step_result == sqlite3.DONE and status == sqlite3.OK then
    return results
  else
    return nil, self:get_error(status)
  end
end

-- Execute a simple statement
-- The statement can optionally return a row (useful for COUNT) statement
-- but this might be another method in the future
-- @param stmt A sqlite3 prepared statement
-- @return true if the statement does not return any row
--         value of the fetched row if the statement returns a row
--         nil if error
-- @return A sqlite3 status code if error
function BaseDao:exec_stmt(stmt)
  -- Execute query
  local results
  local step_result = stmt:step()

  -- Aggregate rows
  if step_result == sqlite3.ROW then
    results = stmt:get_uvalues()
    step_result = stmt:step()
  end

  -- Reset statement and get status code
  local status = stmt:reset()

  -- Error handling
  if step_result == sqlite3.DONE and status == sqlite3.OK then
    if results then return results else return true end;
  else
    return nil, self:get_error(status)
  end
end

-- Execute a statement and return the last inserted rowid
-- useful for INSERTS
-- @param stmt A sqlite3 prepared statement
-- @return The created entity
-- @return A sqlite3 status code if error
function BaseDao:exec_insert_stmt(stmt)
  -- Execute query
  local step_result = stmt:step()

  -- Reset statement and get status code
  local status = stmt:reset()

  -- Error handling
  if step_result == sqlite3.DONE and status == sqlite3.OK then
    return self._db:last_insert_rowid()
  else
    return nil, self:get_error(status)
  end
end


return BaseDao
