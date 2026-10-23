-- приоритет операторов: * выше +, скобки группируют
function calc(x, y, z) return x + y * z end
function grouped(x, y, z) return (x + y) * z end
