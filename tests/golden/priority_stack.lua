-- приоритет операторов: * выше +, скобки группируют
-- @stack
function calc(x, y, z) return x + y * z end
-- @stack
function grouped(x, y, z) return (x + y) * z end
