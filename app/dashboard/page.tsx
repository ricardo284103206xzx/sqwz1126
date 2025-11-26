'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import {
  Table,
  Button,
  Space,
  Tag,
  Modal,
  Form,
  Input,
  InputNumber,
  Radio,
  message,
  Popconfirm,
  Card,
  Row,
  Col,
} from 'antd';
import {
  PlusOutlined,
  LogoutOutlined,
  CheckCircleOutlined,
  CloseCircleOutlined,
  ExclamationCircleOutlined,
} from '@ant-design/icons';
import axios from 'axios';
import dayjs from 'dayjs';

interface Authorization {
  _id: string;
  mt5_account: string;
  authorized_at: string;
  expires_at: string | null;
  is_permanent: boolean;
  duration_days: number;
  status: string;
  notes: string;
  remaining_days: number;
  is_expired: boolean;
  verify_count: number;
}

export default function DashboardPage() {
  const router = useRouter();
  const [loading, setLoading] = useState(false);
  const [authorizations, setAuthorizations] = useState<Authorization[]>([]);
  const [isModalVisible, setIsModalVisible] = useState(false);
  const [form] = Form.useForm();
  const [username, setUsername] = useState('');
  const [durationType, setDurationType] = useState<'days' | 'permanent'>('days');

  useEffect(() => {
    // 检查登录状态
    const token = localStorage.getItem('token');
    const storedUsername = localStorage.getItem('username');
    if (!token) {
      router.push('/login');
      return;
    }
    setUsername(storedUsername || '');
    fetchAuthorizations();
  }, [router]);

  // 配置axios默认header
  const getAxiosConfig = () => {
    const token = localStorage.getItem('token');
    return {
      headers: {
        Authorization: `Bearer ${token}`,
      },
    };
  };

  // 获取授权列表
  const fetchAuthorizations = async () => {
    setLoading(true);
    try {
      const response = await axios.get('/api/admin/authorizations', getAxiosConfig());
      if (response.data.success) {
        setAuthorizations(response.data.data);
      }
    } catch (error: any) {
      if (error.response?.status === 401) {
        message.error('登录已过期，请重新登录');
        localStorage.removeItem('token');
        router.push('/login');
      } else {
        message.error('获取授权列表失败');
      }
    } finally {
      setLoading(false);
    }
  };

  // 添加授权
  const handleAddAuthorization = async (values: any) => {
    try {
      const duration_days = durationType === 'permanent' ? -1 : values.duration_days;
      
      const response = await axios.post(
        '/api/admin/authorizations',
        {
          mt5_account: values.mt5_account,
          duration_days: duration_days,
          notes: values.notes || '',
        },
        getAxiosConfig()
      );

      if (response.data.success) {
        message.success('授权添加成功');
        setIsModalVisible(false);
        form.resetFields();
        fetchAuthorizations();
      } else {
        message.error(response.data.message || '添加失败');
      }
    } catch (error: any) {
      message.error(error.response?.data?.message || '添加失败');
    }
  };

  // 延期授权
  const handleExtendAuthorization = (record: Authorization) => {
    Modal.confirm({
      title: '延期授权',
      content: (
        <Form
          id="extendForm"
          initialValues={{ duration_days: 30 }}
        >
          <Form.Item
            name="duration_days"
            label="延期天数"
            rules={[{ required: true, message: '请输入延期天数' }]}
          >
            <InputNumber min={1} max={3650} style={{ width: '100%' }} />
          </Form.Item>
        </Form>
      ),
      onOk: async () => {
        const form = document.getElementById('extendForm') as any;
        const duration_days = form?.querySelector('input')?.value;
        
        try {
          const response = await axios.put(
            `/api/admin/authorizations/${record._id}`,
            { duration_days: parseInt(duration_days) },
            getAxiosConfig()
          );

          if (response.data.success) {
            message.success('延期成功');
            fetchAuthorizations();
          }
        } catch (error) {
          message.error('延期失败');
        }
      },
    });
  };

  // 取消授权
  const handleCancelAuthorization = async (id: string) => {
    try {
      const response = await axios.delete(
        `/api/admin/authorizations/${id}?action=cancel`,
        getAxiosConfig()
      );

      if (response.data.success) {
        message.success('授权已取消');
        fetchAuthorizations();
      }
    } catch (error) {
      message.error('取消失败');
    }
  };

  // 删除授权
  const handleDeleteAuthorization = async (id: string) => {
    try {
      const response = await axios.delete(
        `/api/admin/authorizations/${id}?action=delete`,
        getAxiosConfig()
      );

      if (response.data.success) {
        message.success('授权已删除');
        fetchAuthorizations();
      }
    } catch (error) {
      message.error('删除失败');
    }
  };

  // 登出
  const handleLogout = () => {
    localStorage.removeItem('token');
    localStorage.removeItem('username');
    message.success('已退出登录');
    router.push('/login');
  };

  // 统计数据
  const stats = {
    total: authorizations.length,
    active: authorizations.filter(a => a.status === 'active' && !a.is_expired).length,
    expired: authorizations.filter(a => a.is_expired || a.status === 'expired').length,
    cancelled: authorizations.filter(a => a.status === 'cancelled').length,
  };

  const columns = [
    {
      title: 'MT5账号',
      dataIndex: 'mt5_account',
      key: 'mt5_account',
      width: 120,
    },
    {
      title: '授权时间',
      dataIndex: 'authorized_at',
      key: 'authorized_at',
      width: 180,
      render: (date: string) => dayjs(date).format('YYYY-MM-DD HH:mm'),
    },
    {
      title: '到期时间',
      dataIndex: 'expires_at',
      key: 'expires_at',
      width: 180,
      render: (date: string | null, record: Authorization) => {
        if (record.is_permanent) {
          return <Tag color="purple">永久</Tag>;
        }
        return date ? dayjs(date).format('YYYY-MM-DD HH:mm') : '-';
      },
    },
    {
      title: '剩余天数',
      dataIndex: 'remaining_days',
      key: 'remaining_days',
      width: 100,
      render: (days: number, record: Authorization) => {
        if (record.is_permanent) return '永久';
        if (days === 0) return <span style={{ color: '#ff4d4f' }}>已过期</span>;
        if (days < 7) return <span style={{ color: '#faad14' }}>{days}天</span>;
        return <span>{days}天</span>;
      },
    },
    {
      title: '状态',
      dataIndex: 'status',
      key: 'status',
      width: 100,
      render: (status: string, record: Authorization) => {
        if (record.is_expired || status === 'expired') {
          return <Tag icon={<CloseCircleOutlined />} color="error">已过期</Tag>;
        }
        if (status === 'cancelled') {
          return <Tag icon={<ExclamationCircleOutlined />} color="default">已取消</Tag>;
        }
        if (record.remaining_days < 7 && !record.is_permanent) {
          return <Tag icon={<ExclamationCircleOutlined />} color="warning">即将过期</Tag>;
        }
        return <Tag icon={<CheckCircleOutlined />} color="success">有效</Tag>;
      },
    },
    {
      title: '验证次数',
      dataIndex: 'verify_count',
      key: 'verify_count',
      width: 100,
    },
    {
      title: '备注',
      dataIndex: 'notes',
      key: 'notes',
      ellipsis: true,
    },
    {
      title: '操作',
      key: 'action',
      width: 200,
      render: (_: any, record: Authorization) => (
        <Space size="small">
          {record.status === 'active' && (
            <>
              <Button
                type="link"
                size="small"
                onClick={() => handleExtendAuthorization(record)}
              >
                延期
              </Button>
              <Popconfirm
                title="确定要取消此授权吗？"
                onConfirm={() => handleCancelAuthorization(record._id)}
              >
                <Button type="link" size="small" danger>
                  取消
                </Button>
              </Popconfirm>
            </>
          )}
          {(record.status === 'expired' || record.status === 'cancelled') && (
            <Popconfirm
              title="确定要删除此记录吗？"
              onConfirm={() => handleDeleteAuthorization(record._id)}
            >
              <Button type="link" size="small" danger>
                删除
              </Button>
            </Popconfirm>
          )}
        </Space>
      ),
    },
  ];

  return (
    <div className="dashboard-container">
      <div className="dashboard-header">
        <h2 style={{ margin: 0 }}>MT5 EA授权管理系统</h2>
        <Space>
          <span>欢迎，{username}</span>
          <Button icon={<LogoutOutlined />} onClick={handleLogout}>
            退出
          </Button>
        </Space>
      </div>

      <div className="dashboard-content">
        {/* 统计卡片 */}
        <Row gutter={16} style={{ marginBottom: 24 }}>
          <Col span={6}>
            <Card>
              <div style={{ textAlign: 'center' }}>
                <div style={{ fontSize: 32, fontWeight: 'bold', color: '#1890ff' }}>
                  {stats.total}
                </div>
                <div style={{ color: '#666' }}>总授权数</div>
              </div>
            </Card>
          </Col>
          <Col span={6}>
            <Card>
              <div style={{ textAlign: 'center' }}>
                <div style={{ fontSize: 32, fontWeight: 'bold', color: '#52c41a' }}>
                  {stats.active}
                </div>
                <div style={{ color: '#666' }}>有效授权</div>
              </div>
            </Card>
          </Col>
          <Col span={6}>
            <Card>
              <div style={{ textAlign: 'center' }}>
                <div style={{ fontSize: 32, fontWeight: 'bold', color: '#ff4d4f' }}>
                  {stats.expired}
                </div>
                <div style={{ color: '#666' }}>已过期</div>
              </div>
            </Card>
          </Col>
          <Col span={6}>
            <Card>
              <div style={{ textAlign: 'center' }}>
                <div style={{ fontSize: 32, fontWeight: 'bold', color: '#d9d9d9' }}>
                  {stats.cancelled}
                </div>
                <div style={{ color: '#666' }}>已取消</div>
              </div>
            </Card>
          </Col>
        </Row>

        {/* 授权列表 */}
        <Card
          title="授权列表"
          extra={
            <Button
              type="primary"
              icon={<PlusOutlined />}
              onClick={() => setIsModalVisible(true)}
            >
              添加授权
            </Button>
          }
        >
          <Table
            columns={columns}
            dataSource={authorizations}
            rowKey="_id"
            loading={loading}
            pagination={{
              pageSize: 10,
              showTotal: (total) => `共 ${total} 条`,
            }}
          />
        </Card>
      </div>

      {/* 添加授权弹窗 */}
      <Modal
        title="添加授权"
        open={isModalVisible}
        onCancel={() => {
          setIsModalVisible(false);
          form.resetFields();
        }}
        onOk={() => form.submit()}
        width={500}
      >
        <Form
          form={form}
          layout="vertical"
          onFinish={handleAddAuthorization}
          initialValues={{ duration_days: 30 }}
        >
          <Form.Item
            name="mt5_account"
            label="MT5账号"
            rules={[{ required: true, message: '请输入MT5账号' }]}
          >
            <Input placeholder="请输入MT5账号" />
          </Form.Item>

          <Form.Item label="授权时长">
            <Radio.Group
              value={durationType}
              onChange={(e) => setDurationType(e.target.value)}
            >
              <Radio value="days">自定义天数</Radio>
              <Radio value="permanent">永久授权</Radio>
            </Radio.Group>
          </Form.Item>

          {durationType === 'days' && (
            <Form.Item
              name="duration_days"
              label="天数"
              rules={[{ required: true, message: '请输入授权天数' }]}
            >
              <InputNumber
                min={1}
                max={3650}
                style={{ width: '100%' }}
                placeholder="请输入授权天数"
              />
            </Form.Item>
          )}

          <Form.Item name="notes" label="备注">
            <Input.TextArea rows={3} placeholder="可选，添加备注信息" />
          </Form.Item>
        </Form>
      </Modal>
    </div>
  );
}

